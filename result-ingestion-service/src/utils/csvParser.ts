import { parse } from "csv-parse";
import { Readable } from "stream";
import { z } from "zod";
import { ResultRow } from "../types/ingestion.types";

const CsvRecordSchema = z.object({
  exam_id: z.string().min(1, "exam_id is required"),
  roll_no: z.string().min(1, "roll_no is required"),
  semester: z.coerce.number().int().positive("semester must be a positive integer"),
  college_code: z.string().min(1, "college_code is required"),
  batch_year: z.coerce.number().int().positive("batch_year must be a positive integer"),
  dept_code: z.string().min(1, "dept_code is required"),
  name: z.string().min(1, "name is required"),
  father_name: z.string().min(1, "father_name is required"),
  gender: z.string().min(1, "gender is required"),
  course: z.string().min(1, "course is required"),
  medium: z.string().min(1, "medium is required"),
  subjects: z.string().transform((val, ctx) => {
    try {
      return JSON.parse(val);
    } catch {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "subjects must be valid JSON"
      });
      return z.NEVER;
    }
  }),
  result_status: z.string().min(1, "result_status is required"),
  sgpa: z
    .string()
    .optional()
    .nullable()
    .transform((val) => (val && val.trim() !== "" ? Number(val) : null)),
  cgpa: z
    .string()
    .optional()
    .nullable()
    .transform((val) => (val && val.trim() !== "" ? Number(val) : null))
});

export interface ParseResult {
  detectedExamId: string;
  collegeGroups: Map<string, ResultRow[]>;
  totalRows: number;
}

export class CsvParser {
  public static async parseStream(stream: Readable): Promise<ParseResult> {
    return new Promise((resolve, reject) => {
      const parser = stream.pipe(
        parse({
          columns: true,
          skip_empty_lines: true,
          trim: true,
          bom: true
        })
      );

      const collegeGroups = new Map<string, ResultRow[]>();
      let detectedExamId = "";
      let totalRows = 0;
      let rowIndex = 0;

      parser.on("data", (rawRecord: Record<string, string>) => {
        rowIndex++;
        const parseResult = CsvRecordSchema.safeParse(rawRecord);
        if (!parseResult.success) {
          reject(
            new Error(
              `Validation error at row ${rowIndex}: ${parseResult.error.errors.map((e) => e.message).join(", ")}`
            )
          );
          parser.destroy();
          return;
        }

        const data = parseResult.data;
        if (!detectedExamId) {
          detectedExamId = data.exam_id;
        }

        const row: ResultRow = {
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
