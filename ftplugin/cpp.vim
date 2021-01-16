let b:dbgCmdResume = 'continue'
let b:dbgCmdExit = 'quit'
let b:dbgCmdStepUp = 'finish'
let b:dbgCmdDelBreakpoint = 'breakpoint delete '
let b:dbgCmdWhere = 'bt'
let b:dbgCmdEval = 'p '
let b:dbgCmdVar = 'v '
call DbgSetupKeyMap()
