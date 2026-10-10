import json

header = "exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa\n"
subjects_json = json.dumps([{"code": "CS601", "name": "DISTRIBUTED SYSTEMS", "credits": 3, "grade": "A"}])
escaped_subjects = f'"{subjects_json.replace(chr(34), chr(34) + chr(34))}"'

with open("scratch/upload-atomicity-fail.csv", "w", encoding="utf-8") as f:
    f.write(header)
    for i in range(1, 501):
        name = "FORCE_TRANSACTION_FAILURE" if i == 250 else f"STUDENT {i}"
        f.write(f"EXAM_ATOMICITY_FAIL,160423{i:06d},6,1604,23,733,{name},PARENT {i},MALE,B.E.,ENG,{escaped_subjects},PASSED,8.0,8.0\n")

print("Atomicity failure file created!")
