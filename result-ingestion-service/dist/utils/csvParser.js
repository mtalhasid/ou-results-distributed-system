"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CsvParser = void 0;
const csv_parse_1 = require("csv-parse");
const zod_1 = require("zod");
const CsvRecordSchema = zod_1.z.object({
    exam_id: zod_1.z.string().min(1, "exam_id is required"),
    roll_no: zod_1.z.string().min(1, "roll_no is required"),
    semester: zod_1.z.coerce.number().int().positive("semester must be a positive integer"),
    college_code: zod_1.z.string().min(1, "college_code is required"),
    batch_year: zod_1.z.coerce.number().int().positive("batch_year must be a positive integer"),
    dept_code: zod_1.z.string().min(1, "dept_code is required"),
    name: zod_1.z.string().min(1, "name is required"),
    father_name: zod_1.z.string().min(1, "father_name is required"),
    gender: zod_1.z.string().min(1, "gender is required"),
    course: zod_1.z.string().min(1, "course is required"),
    medium: zod_1.z.string().min(1, "medium is required"),
    subjects: zod_1.z.string().transform((val, ctx) => {
        try {
            return JSON.parse(val);
        }
        catch {
            ctx.addIssue({
                code: zod_1.z.ZodIssueCode.custom,
                message: "subjects must be valid JSON"
            });
            return zod_1.z.NEVER;
        }
    }),
    result_status: zod_1.z.string().min(1, "result_status is required"),
    sgpa: zod_1.z
        .string()
        .optional()
        .nullable()
        .transform((val) => (val && val.trim() !== "" ? Number(val) : null)),
    cgpa: zod_1.z
        .string()
        .optional()
        .nullable()
        .transform((val) => (val && val.trim() !== "" ? Number(val) : null))
});
class CsvParser {
    static async parseStream(stream) {
        return new Promise((resolve, reject) => {
            const parser = stream.pipe((0, csv_parse_1.parse)({
                columns: true,
                skip_empty_lines: true,
                trim: true,
                bom: true
            }));
            const collegeGroups = new Map();
            let detectedExamId = "";
            let totalRows = 0;
            let rowIndex = 0;
            parser.on("data", (rawRecord) => {
                rowIndex++;
                const parseResult = CsvRecordSchema.safeParse(rawRecord);
                if (!parseResult.success) {
                    reject(new Error(`Validation error at row ${rowIndex}: ${parseResult.error.errors.map((e) => e.message).join(", ")}`));
                    parser.destroy();
                    return;
                }
                const data = parseResult.data;
                if (!detectedExamId) {
                    detectedExamId = data.exam_id;
                }
                const row = {
                    rollNo: data.roll_no,
                    semester: data.semester,
                    collegeCode: data.college_code,
                    batchYear: data.batch_year,
                    deptCode: data.dept_code,
                    name: data.name,
                    fatherName: data.father_name,
                    gender: data.gender,
                    course: data.course,
                    medium: data.medium,
                    subjects: data.subjects,
                    resultStatus: data.result_status,
                    sgpa: data.sgpa,
                    cgpa: data.cgpa
                };
                const collegeList = collegeGroups.get(row.collegeCode) || [];
                collegeList.push(row);
                collegeGroups.set(row.collegeCode, collegeList);
                totalRows++;
            });
            parser.on("end", () => {
                resolve({
                    detectedExamId,
                    collegeGroups,
                    totalRows
                });
            });
            parser.on("error", (err) => {
                reject(err);
            });
        });
    }
}
exports.CsvParser = CsvParser;
//# sourceMappingURL=csvParser.js.map