import json

header = "exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa\n"
subjects_json = json.dumps([
    {"code": "CS601", "name": "DISTRIBUTED SYSTEMS", "credits": 3, "grade": "A"}
])
escaped_subjects = f'"{subjects_json.replace(chr(34), chr(34) + chr(34))}"'

with open("scratch/upload-durability.csv", "w", encoding="utf-8") as f:
    f.write(header)
    for i in range(1, 501):
        f.write(f"EXAM_DURABILITY,160423{i:06d},6,1604,23,733,STUDENT S1_{i},PARENT {i},MALE,B.E. (AICTE),ENGLISH,{escaped_subjects},PASSED,8.50,8.20\n")
    for i in range(1, 501):
        f.write(f"EXAM_DURABILITY,160823{i:06d},6,1608,23,733,STUDENT S2_{i},PARENT {i},FEMALE,B.E. (AICTE),ENGLISH,{escaped_subjects},PASSED,9.10,8.90\n")

print("Created scratch/upload-durability.csv successfully")
