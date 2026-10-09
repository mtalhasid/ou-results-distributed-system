export interface ExamMetadata {
  examId: string;
  title: string;
  resultDate: string; // YYYY-MM-DD format
}

export interface ResultRow {
  rollNo: string;
  semester: number;
  collegeCode: string;
  batchYear: number;
  deptCode: string;
  name: string;
  fatherName: string;
  gender: string;
  course: string;
  medium: string;
  subjects: unknown;
  resultStatus: string;
  sgpa: number | null;
  cgpa: number | null;
}

export interface ResultBatchMessage {
  batchId: string;
  examId: string;
  collegeCode: string;
  uploadedAt: string; // ISO-8601 timestamp string
  exam: ExamMetadata;
  rows: ResultRow[];
}

export interface IngestionResult {
  examId: string;
  totalRows: number;
  batchesPublished: number;
  collegesCount: number;
}
