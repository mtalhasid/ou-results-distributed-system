import http from "k6/http";
import { check, sleep } from "k6";

const manifest = JSON.parse(open("../../load-tests/seed/out/seed-manifest.json"));
const groups = manifest.groups;
const baseUrl = __ENV.BASE_URL || "http://localhost:8082";
const users = Number(__ENV.VUS || 300);

export const options = {
  scenarios: {
    ramp_and_spike: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: "10s", target: Math.floor(users / 2) },
        { duration: "20s", target: Math.floor(users / 2) },
        { duration: "1s", target: users },
        { duration: "20s", target: users },
        { duration: "5s", target: 0 },
      ],
      gracefulRampDown: "5s",
    },
  },
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "max"],
};

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

export default function () {
  const response = http.get(`${baseUrl}/api/results/${requestRollNumber()}`);
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
  sleep(0.1);
}
