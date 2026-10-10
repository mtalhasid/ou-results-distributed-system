with open('scratch/oversized-upload.csv', 'wb') as f:
    f.write(b'exam_id,roll_no,semester,college_code,batch_year,dept_code,name,father_name,gender,course,medium,subjects,result_status,sgpa,cgpa\n')
    chunk = b'OVERSIZED_EXAM,160423000001,6,1604,23,733,STUDENT,PARENT,MALE,B.E.,ENG,"[]",PASSED,8.0,8.0\n'
    target_size = 52 * 1024 * 1024 # 52 MB
    repeat = (target_size // len(chunk)) + 100
    for _ in range(repeat):
        f.write(chunk)
print('Oversized file created!')
