set pagination off
set confirm off
set disable-randomization off
set print frame-arguments none
run
if $_isvoid($_exitcode)
  thread apply all backtrace 80
  quit 1
end
