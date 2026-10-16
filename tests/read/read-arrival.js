import http from "k6/http";
import { check } from "k6";

const manifest = JSON.parse(open("../../load-tests/seed/out/seed-manifest.json"));
const groups = manifest.groups;
const baseUrl = __ENV.BASE_URL || "http://localhost:8082";
const mode = (__ENV.MODE || "uniform").toLowerCase();
const hotSetSize = Number(__ENV.HOT_SET || 3000);
const timeoutSeconds = Number(__ENV.TIMEOUT || 30);

if (!__ENV.PEAK) {
  throw new Error("PEAK is required and must be requests per second.");
}

const peak = Number(__ENV.PEAK);
const maxVus = Number(__ENV.MAXVUS || 300);
if (mode !== "uniform" && mode !== "hot") {
  throw new Error("MODE must be either 'uniform' or 'hot'.");
}
if (!Number.isInteger(peak) || peak < 1) {
  throw new Error("PEAK must be a positive integer.");
}
if (!Number.isInteger(maxVus) || maxVus < 1) {
  throw new Error("MAXVUS must be a positive integer.");
}
if (!Number.isInteger(hotSetSize) || hotSetSize < 1) {
  throw new Error("HOT_SET must be a positive integer.");
}
if (!Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
  throw new Error("TIMEOUT must be a positive number of seconds.");
}

const orderedGroups = [...groups].sort((left, right) =>
  String(left.college_code).localeCompare(String(right.college_code)) ||
  Number(left.batch_year) - Number(right.batch_year) ||
  String(left.dept_code).localeCompare(String(right.dept_code)) ||
  Number(left.roll_min) - Number(right.roll_min)
);
const groupSizes = orderedGroups.map(
  (group) => group.roll_max - group.roll_min + 1
);
const totalRollNumbers = groupSizes.reduce((total, size) => total + size, 0);
if (totalRollNumbers < 1) {
  throw new Error("Seed manifest does not contain any valid roll numbers.");
}

function formatRollNumber(group, roll) {
  return `${group.college_code}${String(group.batch_year).padStart(2, "0")}${group.dept_code}${String(roll).padStart(3, "0")}`;
}

function createHotSet(size) {
  const sampleCount = Math.min(size, totalRollNumbers);
  const selected = [];
  let groupIndex = 0;
  let groupOffset = 0;

  for (let index = 0; index < sampleCount; index++) {
    const rollIndex = Math.floor(index * totalRollNumbers / sampleCount);
    while (rollIndex >= groupOffset + groupSizes[groupIndex]) {
      groupOffset += groupSizes[groupIndex];
      groupIndex++;
    }
    const group = orderedGroups[groupIndex];
    const roll = group.roll_min + rollIndex - groupOffset;
    selected.push(formatRollNumber(group, roll));
  }
  return selected;
}

const hotSet = mode === "hot" ? createHotSet(hotSetSize) : [];

function validRollNumber() {
  const group = groups[Math.floor(Math.random() * groups.length)];
  const roll = group.roll_min + Math.floor(Math.random() * (group.roll_max - group.roll_min + 1));
  return formatRollNumber(group, roll);
}

function invalidRollNumber() {
  const group = groups[Math.floor(Math.random() * groups.length)];
  return `${group.college_code}${String(group.batch_year).padStart(2, "0")}${group.dept_code}900`;
}

function requestRollNumber() {
  if (Math.random() >= 0.95) {
    return invalidRollNumber();
  }
  if (mode === "hot") {
    return hotSet[Math.floor(Math.random() * hotSet.length)];
  }
  return validRollNumber();
}

export const options = {
  scenarios: {
    arrival_spike: {
      executor: "ramping-arrival-rate",
      startRate: 5,
      timeUnit: "1s",
      preAllocatedVUs: Math.max(50, Math.ceil(peak / 2)),
      maxVUs: maxVus,
      stages: [
        { duration: "20s", target: Math.ceil(peak * 0.25) },
        { duration: "5s", target: peak },
        { duration: "30s", target: peak },
        { duration: "5s", target: 0 },
      ],
      gracefulStop: "30s",
    },
  },
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "max"],
};

export default function () {
  const response = http.get(
    `${baseUrl}/api/results/${requestRollNumber()}`,
    { timeout: `${timeoutSeconds}s` }
  );
  check(response, {
    "response is successful": (res) => res.status === 200,
    "response is a result list": (res) => {
      try {
        return Array.isArray(res.json().data);
      } catch (_) {
        return false;
      }
    },
  });
}
