import http from "k6/http";
import { check } from "k6";
import { Counter, Trend } from "k6/metrics";
import exec from "k6/execution";

const baseUrl = __ENV.BASE_URL || "http://localhost:8081";
const selectedScenario = (__ENV.SCENARIO || "").toLowerCase();
const validRollNumber = __ENV.VALID_ROLL_NUMBER || "160423733001";

if (selectedScenario !== "invalid" && selectedScenario !== "burst") {
  throw new Error("SCENARIO must be either 'invalid' or 'burst'.");
}

const statusCodes = {
  200: new Counter("gateway_status_200"),
  400: new Counter("gateway_status_400"),
  429: new Counter("gateway_status_429"),
  503: new Counter("gateway_status_503"),
  other: new Counter("gateway_status_other"),
};
const acceptedDuration = new Trend("gateway_accepted_duration");
const rejectedDuration = new Trend("gateway_rejected_duration");

export const options = {
  scenarios: selectedScenario === "invalid"
    ? {
        invalid_roll_numbers: {
          executor: "constant-arrival-rate",
          rate: 50,
          timeUnit: "1s",
          duration: "20s",
          preAllocatedVUs: 100,
          maxVUs: 200,
          exec: "invalidRequests",
        },
      }
    : {
        rate_limit_burst: {
          executor: "constant-arrival-rate",
          rate: 100,
          timeUnit: "1s",
          duration: "10s",
          preAllocatedVUs: 100,
          maxVUs: 300,
          exec: "burstRequests",
        },
      },
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "max"],
};

const invalidRollNumbers = [
  "16042373301",
  "16A423733001",
  "999923737017",
];

function recordResponse(response, expectedStatuses, checkName) {
  const statusCounter = statusCodes[response.status] || statusCodes.other;
  statusCounter.add(1);

  if (response.status >= 200 && response.status < 400) {
    acceptedDuration.add(response.timings.duration);
  } else if (response.status >= 400) {
    rejectedDuration.add(response.timings.duration);
  }

  check(response, {
    [checkName]: (res) => expectedStatuses.includes(res.status),
  });
}

export function invalidRequests() {
  const iteration = exec.scenario.iterationInTest;
  const rollNumber = invalidRollNumbers[iteration % invalidRollNumbers.length];
  const response = http.get(`${baseUrl}/api/results/${rollNumber}`);
  recordResponse(response, [400], "invalid roll number returns 400");
}

export function burstRequests() {
  const response = http.get(
    `${baseUrl}/api/results/${validRollNumber}`,
  );
  recordResponse(response, [200, 429], "burst request returns 200 or 429");
}
