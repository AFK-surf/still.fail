set pagination off
set confirm off
set disable-randomization off
set print frame-arguments none
run
if $_isvoid($_exitcode)
  frame 0
  info args
  info locals
  info registers
  thread apply all backtrace 250
  quit 1
end
