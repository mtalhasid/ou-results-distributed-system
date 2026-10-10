import json

header = "exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa\n"
subjects_json = json.dumps([
    {"code": "CS601", "name": "DISTRIBUTED SYSTEMS", "credits": 3, "grade": "A"},
    {"code": "CS602", "name": "DATABASE INTERNALS", "credits": 3, "grade": "B"},
    {"code": "CS603", "name": "COMPUTER NETWORKS", "credits": 3, "grade": "A"},
    {"code": "CS604", "name": "OPERATING SYSTEMS", "credits": 3, "grade": "S"},
    {"code": "CS605", "name": "SOFTWARE ENGINEERING", "credits": 2, "grade": "A"},
    {"code": "CS606", "name": "DISTRIBUTED LAB", "credits": 2, "grade": "A"}
])
escaped_subjects = f'"{subjects_json.replace(chr(34), chr(34) + chr(34))}"'

def generate_csv(filename, exam_id, shard1_count, shard2_count):
    with open(filename, "w", encoding="utf-8") as f:
        f.write(header)
        # Shard 1 rows (College 1604)
        for i in range(1, shard1_count + 1):
            roll_no = f"160423{i:06d}"
            name = f"STUDENT S1_{i}"
            f.write(f"{exam_id},{roll_no},6,1604,23,733,{name},PARENT {i},MALE,B.E. (AICTE),ENGLISH,{escaped_subjects},PASSED,8.50,8.20\n")
        # Shard 2 rows (College 1608)
        for i in range(1, shard2_count + 1):
            roll_no = f"160823{i:06d}"
            name = f"STUDENT S2_{i}"
            f.write(f"{exam_id},{roll_no},6,1608,23,733,{name},PARENT {i},FEMALE,B.E. (AICTE),ENGLISH,{escaped_subjects},PASSED,9.10,8.90\n")

print("Generating 5k file...")
generate_csv("scratch/upload-5k.csv", "EXAM_SCALE_5K", 2500, 2500)
print("Generating 10k file...")
generate_csv("scratch/upload-10k.csv", "EXAM_SCALE_10K", 5000, 5000)
print("Done!")
