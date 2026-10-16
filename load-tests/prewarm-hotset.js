import http from "k6/http";
import exec from "k6/execution";

const manifest = JSON.parse(open("./seed/out/seed-manifest.json"));
const groups = manifest.groups;
const baseUrl = __ENV.BASE_URL || "http://localhost:8081";
const hotSetSize = Number(__ENV.HOT_SET || 3000);

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

const hotSet = createHotSet(hotSetSize);

export const options = {
  scenarios: {
    warmup: {
      executor: "shared-iterations",
      vus: 20,
      iterations: hotSet.length,
      maxDuration: "60s",
    },
  },
};

export default function () {
  const rollNo = hotSet[exec.scenario.iterationInTest];
  if (rollNo) {
    http.get(`${baseUrl}/api/results/${rollNo}`, { timeout: "15s" });
  }
}
