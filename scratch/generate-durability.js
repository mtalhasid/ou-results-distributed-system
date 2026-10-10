const fs = require('fs');

const lines = ['roll_no,name,college_code,exam_id,semester,subjects,cgpa'];
const subjects = '"[{\\"subject_code\\":\\"CS401\\",\\"subject_name\\":\\"OS\\",\\"credits\\":4,\\"grade\\":\\"A\\"}]"';

for (let i = 1; i <= 500; i++) {
  const roll = '160422733' + String(i).padStart(3, '0');
  lines.push(`${roll},Durability Student ${i},1604,EXAM_DURABILITY,4,${subjects},8.50`);
}
for (let i = 1; i <= 500; i++) {
  const roll = '160822733' + String(i).padStart(3, '0');
  lines.push(`${roll},Durability Student ${i},1608,EXAM_DURABILITY,4,${subjects},8.50`);
}

fs.writeFileSync('scratch/upload-durability.csv', lines.join('\n'), 'utf8');
console.log('Created scratch/upload-durability.csv with ' + (lines.length - 1) + ' rows');
