import http from "k6/http";
import { check } from "k6";

const manifest = JSON.parse(open("../seed/out/seed-manifest.json"));
const groups = manifest.groups;
const baseUrl = __ENV.BASE_URL || "http://localhost:8082";

if (!__ENV.PEAK) {
  throw new Error("PEAK is required and must be requests per second.");
}

const peak = Number(__ENV.PEAK);
const maxVus = Number(__ENV.MAXVUS || 300);
if (!Number.isInteger(peak) || peak < 1) {
  throw new Error("PEAK must be a positive integer.");
}
if (!Number.isInteger(maxVus) || maxVus < 1) {
  throw new Error("MAXVUS must be a positive integer.");
}

function validRollNumber() {
  const group = groups[Math.floor(Math.random() * groups.length)];
  const roll = group.roll_min + Math.floor(Math.random() * (group.roll_max - group.roll_min + 1));
  return `${group.college_code}${String(group.batch_year).padStart(2, "0")}${group.dept_code}${String(roll).padStart(3, "0")}`;
}

function requestRollNumber() {
  if (Math.random() >= 0.95) {
    const group = groups[Math.floor(Math.random() * groups.length)];
    return `${group.college_code}${String(group.batch_year).padStart(2, "0")}${group.dept_code}900`;
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
    { timeout: "30s" }
  );
  check(response, {
    "response is successful": (res) => res.status === 200,
    "response is a result list": (res) => {
      try {
        return Array.isArray(res.json());
      } catch (_) {
        return false;
      }
    },
  });
}
