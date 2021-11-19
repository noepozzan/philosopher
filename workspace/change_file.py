import sys

file_name = sys.argv[2]

with open(file_name, "r") as f:
	file = f.readlines()
	
file[1] = "database_name = {}\n".format(sys.argv[1])
file[10] = "calibrate_mass = 0\n"

new_string = ""
for line in file:
	new_string += line

print(new_string)

with open(file_name, "w") as f:
	f.write(new_string)
