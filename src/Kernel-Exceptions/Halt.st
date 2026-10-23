Exception subclass: #Halt
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Exceptions'!

Halt comment: 'I am signaled by halt. Unhandled, I open a debugger (or print the stack when headless); proceeding resumes after the halt.'!
