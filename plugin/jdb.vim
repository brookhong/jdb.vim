let s:lldbFramePattern = 'frame #\(\d\+\): 0x\w\+ [^#]* at \([^:]\+\):\([1-9]\d*\)\%(:\d\+\)\?'
let s:completeLine = ""
function! s:OnProcessResume()
    silent exec "sign unplace ".s:cursign
    let s:bpLine = 0
endfunction

function! s:UpdateConsoleName(pid)
    let t:pid = a:pid
    let buf = substitute(g:jdbBuf, '\d\+>$', a:pid.'>', '')
    if g:jdbBuf != buf
        let g:jdbBuf = buf
        let lastWin = <SID>FocusConsole()
        exec 'file '.g:jdbBuf
        if lastWin != 0
            exec lastWin."wincmd w"
        endif
    endif
endfunction

function! s:OnQuitJDB()
    call <SID>OnProcessResume()
    if exists("g:jdbBuf")
        execute bufwinnr(g:jdbBuf)."wincmd w"
        bd
        unlet g:jdbBuf
    endif
endfunction

function! s:ShowHelp()
    let dbgBufHelp = g:jdbBuf.' Help'
    execute 'tabnew '.dbgBufHelp
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal ff=unix
    setlocal nolist
    nnoremap <buffer> <silent> q :q<CR>
    if line('$') == 1
        call append(0, s:Help)
        1
    endif
endfunction

function! s:Chansend(chan, data)
    if has('nvim')
        call chansend(a:chan, a:data)
    else
        call ch_sendraw(a:chan, a:data)
    endif
endfunction

function! s:SendDbgCmd(cmd)
    if exists("t:dbgChannel")
        call WriteToFileDedup(substitute(a:cmd, "\n", '', ''), g:debuggerCmdHistory)
        for c in split(a:cmd, '\\n')
            if c =~ 'attach \d\+' && t:pid != 0
                call s:Chansend(t:dbgChannel, "process detach\n")
            endif
            call s:Chansend(t:dbgChannel, c."\n")
        endfor
    endif
endfunction

function! s:SendDbgCmdInConsole(cmd)
    let s:CaptureHelp = 0
    call <SID>ClearOutputFromLastCommand()
    call <SID>SendDbgCmd(a:cmd)
endfunction

function! s:ParseStackFile()
    let cl =getline(".")
    let ff = matchlist(cl, '  \[\d\+\] \(\S\+\)\.\(\S\+\) (\(\S\+\).java:\([,0-9]\+\))')
    if len(ff) > 0
        call <SID>PlaceCursorForJava(substitute(ff[1], '\.\a\+$' , '.'.ff[3], ''), ff[4])
        return 1
    endif

    let ff = matchlist(cl, '^#\(\d\+\)\s\+0x\w\+\> in ')
    if len(ff) > 0
        call <SID>SendDbgCmdInConsole("frame ".ff[1]."\\nbt\n")
        return 1
    endif

    " lldb frame from bt
    let ff = matchlist(cl, '^  [ \*] '.s:lldbFramePattern)
    if len(ff) > 0
        call <SID>SendDbgCmdInConsole("f ".ff[1]."\\nbt\n")
        return 1
    endif

    if exists("s:exeDir")
        let ff = matchlist(cl, '.* at \([^:]\+\):\(\d\+\)')
        if len(ff) == 0
            let ff = matchlist(cl, '^      LineEntry: \[0x\w\+-0x\w\+): \([^:]\+\):\(\d\+\)')
        endif
        if len(ff) > 0
            let s:bpFile = <SID>MakeSourcePath(s:exeDir, ff[1])
            let s:bpLine = ff[2]
            call <SID>PlaceCursor(s:bpFile, s:bpLine)
            return 1
        endif
    endif
    return 0
endfunction

function! s:GetSplitterLine()
    let r = 1
    for line in getline(0, '$')
        if line == s:splitter
            return r
        endif
        let r = r + 1
    endfor
    call append(0, s:splitter)
    return 1
endfunction

function! s:FocusConsole()
    let ret = 0
    if !exists("b:lordBuf")
        let ret = bufwinnr('%')
        exec bufwinnr(g:jdbBuf)."wincmd w"
    endif
    return ret
endfunction

function! s:FocusCodeWin()
    let ret = 0
    if !exists('b:dbgCmdResume')
        for w in range(1, winnr('$'))
            if getbufvar(winbufnr(w), 'dbgCmdResume') != ""
                let ret = bufwinnr('%')
                exec w."wincmd w"
                break
            endif
        endfor
    endif
    return ret
endfunction

function! s:FocusTab()
    let ret = 0
    if !exists('t:dbgChannel')
        for t in range(1, tabpagenr('$'))
            if gettabvar(t, 'dbgChannel') != ""
                let ret = tabpagenr()
                exec "tabn ".t
                break
            endif
        endfor
    endif
    return ret
endfunction

function! s:ClearOutputFromLastCommand()
    if bufwinnr(g:jdbBuf) == -1
        exec 'sb '.bufnr(g:jdbBuf)
    endif

    let lastWin = <SID>FocusConsole()

    if line('$') >= winheight('%')-1
        let pos = <SID>GetSplitterLine()
        if pos > 0
            let ln = line('.')
            let pos = pos + 1
            exec pos.',$d _'
            exec ln
        endif
    endif
    if lastWin != 0
        exec lastWin."wincmd w"
    endif
endfunction

function! s:ConsoleOnEnter()
    let ls = <SID>GetSplitterLine()
    if line('.') < ls
        call <SID>SendDbgCmdInConsole(getline('.'))
    else
        call <SID>ParseStackFile()
    endif
endfunction

function! s:BreakDebugger()
    if has('nvim')
        call jobstop(s:jdbJob)
    else
        call job_stop(s:jdbJob, "int")
    endif
endfunction

function! WriteToFileDedup(word, fileName)
  let found = 0
  if filereadable(a:fileName)
    let lines = readfile(a:fileName)
    if index(lines, a:word) != -1
      let found = 1
    endif
  endif
  if found == 0
    call writefile([a:word], a:fileName, "a")
  endif
endfunction

fun! CompleteDebuggerCmd(findstart, base)
    if a:findstart
        " locate the start of the word
        return 0
    else
        " find months matching with "a:base"
        let res = []
        for m in readfile(g:debuggerCmdHistory)
            if m =~ a:base
                call add(res, m)
            endif
        endfor
        return res
    endif
endfun

function! s:ExecuteCmd()
    let ls = <SID>GetSplitterLine()
    if line('.') < ls
        " call <SID>SendDbgCmdInConsole(getline('.'))
        return 1
    else
        return 0
    endif
endfunction

if isdirectory($HOME.'/.jdb.vim') == 0
  call mkdir($HOME.'/.jdb.vim')
endif
let s:splitter = "====================output from last command===================="
function! s:NewConsole(bufName, lordBuf, debugger)
    execute 'silent new '.a:bufName
    setlocal enc=utf-8
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal noreadonly
    setlocal ff=unix
    setlocal nolist
    let b:lordBuf = a:lordBuf
    let dbg = substitute(a:debugger, ' .*', '', '')
    let g:debuggerCmdHistory = $HOME.'/.jdb.vim/'.dbg.'_history'
    let lastCommand = "help"
    if filereadable(g:debuggerCmdHistory)
        let history = readfile(g:debuggerCmdHistory)
        if len(history) > 0
            let lastCommand = history[-1]
        endif
    endif
    normal ggdG
    call append(0, [lastCommand, s:splitter])
    nnoremap <silent> <buffer> <CR> :call <SID>ConsoleOnEnter()<CR>
    nnoremap <silent> <buffer> <C-c> :call <SID>BreakDebugger()<CR>
    setlocal completefunc=CompleteDebuggerCmd
    inoremap <buffer> <silent> <expr><Tab> pumvisible() ? "\<C-n>" : "\<C-x>\<C-u>"
    inoremap <buffer> <silent> <expr><C-d> pumvisible() ? "\<C-x> \<C-u>" : "\<C-u>"
    inoremap <buffer> <silent> <expr><Cr> <SID>ExecuteCmd() ? "<Esc>" : "<Cr>"
    call DbgSetupKeyMap()
    1
endfunction

function! s:IsAttached()
    if has('nvim')
        return jobwait([t:dbgChannel], 0)[0] == -1
    else
        return exists("t:dbgChannel") && ch_status(t:dbgChannel) == "open"
    endif
endfunction

function! s:GetJavaFile(className)
    let l:mainClassName = substitute(a:className, '\$.*', '', '')
    if has_key(g:mapClassFile, l:mainClassName)
        let javaFile = substitute(g:mapClassFile[l:mainClassName], ':.*', '', '')
    else
        let javaFile = substitute(l:mainClassName, '\.', '/', 'g').".java"
    endif
    for dir in g:sourcepaths
        call writefile(['check file '.dir.javaFile], $HOME."/.jdb.vim.log", "a")
        if filereadable(dir.javaFile)
            return dir.javaFile
        end
    endfor
    return ""
endfunction

function! s:PlaceCursorForJava(className, lineNo)
    let javaFile = <SID>GetJavaFile(a:className)
    if javaFile != ""
        call <SID>PlaceCursor(javaFile, a:lineNo)
        let s:bpFile = javaFile
        let s:bpLine = a:lineNo
    endif
endfunction

function! s:PlaceCursor(fileName, lineNo)
    call <SID>FocusTab()
    let restoreFocus = 0
    let lastWin = <SID>FocusCodeWin()
    silent exec "sign unplace ".s:cursign
    silent exec "edit ".a:fileName
    silent exec 'sign place '.s:cursign.' name=current line='.a:lineNo.' file='.a:fileName
    exec a:lineNo
    " redraw!
    normal zz
    if lastWin != 0
        exec lastWin."wincmd w"
    endif
endfunction

function! s:DbgErrHandler(channel, msg)
    if a:msg == 'error: Process must be launched.'
        call <SID>UpdateConsoleName(0)
    endif
    call writefile(['[E] '.a:msg], $HOME."/.jdb.vim.log", "a")
    if exists("g:jdbBuf")
        call appendbufline(bufnr(g:jdbBuf), '$', a:msg)
    endif
endfunction

function! s:DbgExitHandler(channel, msg)
    call <SID>OnQuitJDB()
endfunction

function! SetJVMFrame(frame)
    let step = a:frame - s:currentFrame
    echo step
    if step > 0
        call <SID>SendDbgCmdInConsole('up '.step."\nwhere\n")
    elseif step < 0
        call <SID>SendDbgCmdInConsole('down '.-step."\nwhere\n")
    endif
endfunction

function! s:JdbOutHandler(channel, msg)
    call writefile([a:msg], $HOME."/.jdb.vim.log", "a")
    if s:CaptureHelp
        call add(s:Help, a:msg)
        return
    endif

    if a:msg =~ '^  \S'
        let s:completeLine = s:completeLine.a:msg
    elseif a:msg =~ '^\S'
        let s:completeLine = a:msg
    endif

    let ff = matchlist(s:completeLine, '\(Step completed: \|Breakpoint hit: \|\)"thread=\([^"]\+\)", \(\S\+\)\.\(\S\+\)(), line=\([0-9,]\+\) bci=\(\d\+\)')
    if len(ff) > 0
        call <SID>PlaceCursorForJava(ff[3], substitute(ff[5], ",", '', 'g'))
        return
    endif

    if s:completeLine == "> Nothing suspended." || s:completeLine =~ '\S\+ All threads resumed.$'
        call <SID>OnProcessResume()
        return
    endif

    let ff = matchlist(s:completeLine, '^.* Unable to set breakpoint \([^:]\+\):\(\d\+\) : No code at line \2 in \1$')
    if len(ff)
        call s:Chansend(t:dbgChannel, "clear ".ff[1].":".ff[2]."\n")
        " try to set breakpoints for nested classes if current class is an outer one
        if stridx(ff[1], '$') == -1
            call s:Chansend(t:dbgChannel, "class ".ff[1]."\n")
            let s:breakptOuterClass = ff[1]
            let s:breakptInNestedClass = ff[2]
        elseif has_key(g:mapClassFile, ff[1])
            call remove(g:mapClassFile, ff[1])
        endif
        return
    endif

    let ff = matchlist(s:completeLine, '^nested: \(\S\+\)$')
    if len(ff) && exists('s:breakptInNestedClass')
        call s:Chansend(t:dbgChannel, "stop at ".ff[1].":".s:breakptInNestedClass."\n")
        let g:mapClassFile[ff[1]] = g:mapClassFile[substitute(ff[1], '\$.*', '', '')]
        return
    endif

    let ff = matchlist(s:completeLine, '^.*\[\d\+\]\s\+\[1\] ')
    if len(ff)
        let s:completeLine = substitute(s:completeLine, '^.*\[\d\+\]\s\+\[1\] ', '[1] ', '')
    endif
    if len(ff) == 0 || s:completeLine =~ '^\[1\] '
        let stackTrace = []
        let frames = split(substitute(s:completeLine, '  \(\[\d\+\]\) ', '\n\1 ', 'g'), '\n')
        for frame in frames
            let ffp = matchlist(frame, '\[\d\+\] \(\S\+\)\.\([^\.]\+\) ([^:]\+:\(\d\+\))')
            if len(ffp)
                call add(stackTrace, <SID>GetJavaFile(ffp[1]).':'.ffp[3].':'.ffp[2])
            endif
        endfor
        if len(stackTrace) > 1
            call <SID>FocusCodeWin()
            lgetexpr stackTrace
            call setloclist(0, [], 'r', { 'title': 'JVM Call Stack' })
        endif
        let s:currentFrame = 1
    endif

    let ff = matchlist(s:completeLine, '^.*\[\d\+\]\s\+\[\(\d\+\)\] ')
    if len(ff)
        let s:currentFrame = ff[1]
    endif

    if exists('s:breakptInNestedClass')
        let ff = matchlist(s:completeLine, '^> Set breakpoint '.s:breakptOuterClass.'$1:'.s:breakptInNestedClass.'$')
        if len(ff)
            unlet s:breakptOuterClass
            unlet s:breakptInNestedClass
            return
        endif
    endif
endfunction

function! s:NeoWrap(handler, channel, msg, event)
    if type(a:msg) == type([])
        for msg in a:msg
            call function(a:handler)(a:channel, msg)
            if exists("g:jdbBuf")
                call appendbufline(bufnr(g:jdbBuf), '$', msg)
            endif
        endfor
    else
        call function(a:handler)(a:channel, a:msg)
    endif
endfunction

let s:stackTrace = []
function! LatestStackTraceToLocationList(timer)
    lgetexpr s:stackTrace
    lfirst
endfunction

function! s:MakeSourcePath(root, rp)
    let fp = a:rp
    if a:rp[0] != '/'
        let fp = a:root.a:rp
    endif
    return fp
endfunction

let s:dbGBreakPoints = {}
function! s:GdbOutHandler(channel, msg)
    call writefile([a:msg], $HOME."/.jdb.vim.log", "a")
    if s:CaptureHelp
        call add(s:Help, a:msg)
        return
    endif

    if a:msg =~ '^    \S'
        let s:completeLine = s:completeLine.a:msg
    elseif a:msg =~ '^\S'
        let s:completeLine = a:msg
    endif

    let ff = matchlist(s:completeLine, '^(gdb) Breakpoint \(\d\+\) at 0x\w\+: file .*/\([^,]\+\), line \(\d\+\).$')
    if len(ff)
        let s:dbGBreakPoints[ff[2].':'.ff[3]] = ff[1]
        return
    endif

    let ff = matchlist(s:completeLine, "exe = '\\([^']\\+\\)'")
    if len(ff) > 0
        let s:exeDir = substitute(ff[1], '/[^/]\+$', '/', '')
        call s:Chansend(t:dbgChannel, "cd ".s:exeDir."\n")
        call s:Chansend(t:dbgChannel, "attach ".s:pidToAttach."\n")
        for bp in <SID>GetBreakPoints()
            call s:Chansend(t:dbgChannel, "break ".substitute(bp[0], '.*/', '', '').":".bp[1]."\n")
        endfor
        return
    endif

    if exists("s:exeDir")
        " let ff = matchlist(s:completeLine, '^\(\((gdb) \)\?#\d\+\)\@!\S.* at \([^:]\+\):\(\d\+\)')
        let ff = matchlist(s:completeLine, 'Thread \d\+ ".*" hit Breakpoint \(\d\+\), .* at \([^:]\+\):\(\d\+\)')
        if len(ff) == 0
            " let ff = matchlist(s:completeLine, '^(gdb) #\d\+\s\+0x\w\+\> in .* at \([^:]\+\):\(\d\+\)')
            let ff = matchlist(s:completeLine, '^(gdb) \(#\d\+ \)\@!.* at \([^:]\+\):\(\d\+\)')
        endif
        if len(ff) == 0
            let ff = matchlist(s:completeLine, '^0x\w\+ in \(.*\) at \([^:]\+\):\(\d\+\)')
        endif
        if len(ff) > 0
            let s:bpFile = <SID>MakeSourcePath(s:exeDir, ff[2])
            let s:bpLine = ff[3]
            call <SID>PlaceCursor(s:bpFile, s:bpLine)
            return
        endif
    endif

    let ff = matchlist(s:completeLine, '(gdb) \(\d\+\)\t.*')
    if len(ff) > 0
        let s:bpLine = ff[1]
        call <SID>PlaceCursor(s:bpFile, s:bpLine)
        return
    endif

    let ff = matchlist(s:completeLine, '^\((gdb) \)\?#\d\+\s\+0x\w\+\> in \(.*)\) \(&& \)\?(.*)\s\+at \([^:]\+\)\(:\d\+\)\?$')
    if len(ff) > 0 && ff[5] != ""
        let cf = s:exeDir.ff[4].ff[5].':'.ff[2]
        if ff[1] == '(gdb) '
            let s:stackTrace = [cf]
            let timer = timer_start(2000, 'LatestStackTraceToLocationList')
        else
            call add(s:stackTrace, cf)
        endif
    endif

    if s:completeLine == '(gdb) Continuing.'
        call <SID>OnProcessResume()
        return
    endif
endfunction

function! s:SetFrame()
    if exists("t:dbgChannel")
        let qfInfo = getloclist(0, {'idx':0, 'title':0})
        if qfInfo.idx > 0
            if qfInfo.title == 'Call Stack'
                call <SID>SendDbgCmdInConsole("f ".(qfInfo.idx - 1)."\n")
            else
                call SetJVMFrame(qfInfo.idx)
            endif
        endif
    endif
endfunction

aug DBGFront
    au!
    au! User LocationPosChanged call <SID>SetFrame()
aug END

function! s:LldbOutHandler(channel, msg)
    call writefile([a:msg], $HOME."/.jdb.vim.log", "a")
    if a:msg =~ '^(lldb) ' && a:msg != '(lldb) help'
        let s:CaptureHelp = 0
        call <SID>ClearOutputFromLastCommand()
    endif

    if s:CaptureHelp
        call add(s:Help, a:msg)
        return
    endif

    if a:msg =~ '^  [ \*] \S'
        let s:completeLine = s:completeLine.a:msg
    elseif a:msg =~ '^\S'
        let s:completeLine = a:msg
    endif

    let ff = matchlist(s:completeLine, '^Process \(\d\+\) stopped$')
    if len(ff)
        call <SID>UpdateConsoleName(ff[1])
        return
    endif

    let ff = matchlist(s:completeLine, '^Breakpoint \(\d\+\): where = .* at \([^:]\+\):\(\d\+\):\d\+, address = 0x\w\+$')
    if len(ff)
        let s:dbGBreakPoints[ff[2].':'.ff[3]] = ff[1]
        return
    endif

    let ff = matchlist(s:completeLine, '^Breakpoint \(\d\+\): \d\+ locations.$')
    if len(ff)
        let s:dbGBreakPoints[s:dbgBpKey] = ff[1]
        return
    endif

    if exists("s:exeDir")
        let ff = matchlist(s:completeLine, "^[\\* ] thread #\\d\\+, \\%(name = '[^']\\+', \\)\\?\\%(queue = '[^']\\+', \\)\\?stop reason = [^#]\\{-}".s:lldbFramePattern)
        if len(ff) == 0
            let ff = matchlist(s:completeLine, "^\\* thread #\\d\\+, name = '[^']\\+', \\%(queue = '[^']\\+', \\)\\?stop reason = [^#]\\+    ".s:lldbFramePattern)
        else
            let stackTrace = []
            let frames = split(substitute(s:completeLine, '\<frame #\d\+', '\n&', 'g'), '\n')
            let lastf = ""
            for frame in frames
                let ffp = matchlist(frame, 'frame #\d\+: 0x\w\+ [^`]\+`\([^#]*\) at \([^:]\+\):\(\d\+\)')
                if len(ffp) > 0 && ffp[3] > 0
                    let lastf = <SID>MakeSourcePath(s:exeDir, ffp[2]).':'.ffp[3].':'
                else
                    let ffp = matchlist(frame, 'frame #\d\+: 0x\w\+ [^`]\+`\([^#]*\)')
                endif
                if len(ffp) > 0
                    call add(stackTrace, lastf.ffp[1])
                elseif lastf != ""
                    call writefile(["Unexpected frame: ".frame], $HOME."/.jdb.vim.log", "a")
                endif
            endfor
            if len(stackTrace) > 1
                call <SID>FocusCodeWin()
                lgetexpr stackTrace
                call setloclist(0, [], 'r', { 'title': 'Call Stack' })
            endif
        endif
        if len(ff) == 0
            let ff = matchlist(s:completeLine, s:lldbFramePattern)
        endif
        if len(ff) > 0 && (!exists('s:bpFile') || s:bpFile != <SID>MakeSourcePath(s:exeDir, ff[2]) || s:bpLine != ff[3])
            let s:bpFile = <SID>MakeSourcePath(s:exeDir, ff[2])
            let s:bpLine = ff[3]
            call <SID>PlaceCursor(s:bpFile, s:bpLine)
            return 1
        endif
    else
        let ff = matchlist(s:completeLine, '^Executable module set to "\(.\{-}/\)[^\/]*.app.*')
        if len(ff) == 0
            let ff = matchlist(s:completeLine, '^* target #\d\+: \(.\{-}/\)[^\/]*.app.*')
        endif
        if len(ff) == 0
            let ff = matchlist(s:completeLine, '^Current executable set to .\(.\{-}/\)[^\/]*.app.*')
        endif
        if len(ff) == 0
            " for lldb under linux
            let ff = matchlist(s:completeLine, '^Executable module set to "\(.*\/\)[^"]\+')
        endif
        if len(ff) > 0
            let s:exeDir = ff[1]
        endif
    endif

    if s:completeLine =~ '^Process \d\+ resuming$'
        call <SID>OnProcessResume()
        return
    endif

    if s:completeLine =~ '^Process \d\+ detached$' || s:completeLine =~ '^Process \d\+ exited with status = '
        call <SID>UpdateConsoleName(0)
        return
    endif
endfunction

if !exists('g:sourcepaths ')
    let g:sourcepaths = [""]
endif
if !exists('g:mapClassFile')
    let g:mapClassFile = {}
endif
function! s:GetClassNameFromFile(fn, ln)
    let pos = a:fn.':'.a:ln
    let candidates = keys(filter(g:mapClassFile, 'v:val == "'.pos.'"'))
    if len(candidates)
        return candidates[0]
    endif

    let lines = readfile(a:fn)
    let lpack = 0
    let packageName = ""

    let l:ln = len(lines) - 1

    while packageName == "" && lpack < l:ln
        let ff = matchlist(lines[lpack], '^package\s\+\(\S\+\);\r*$')
        if len(ff) > 1
            let packageName = ff[1]
        endif
        let lpack = lpack + 1
    endwhile

    if len(packageName) == 0
        let lpack = 0
    endif

    let lclass = lpack
    let mainClassName = ""
    let classPattern = '^\s*\%(public\s\+\)\?\%(static\s\+\)\?\%(final\s\+\)\?\%(abstract\s\+\)\?\(class\|interface\)\s\+\(\w\+\)'
    while mainClassName == "" && l:ln > lclass
        let ff = matchlist(lines[lclass], classPattern)
        if len(ff) > 2
            let mainClassName = ff[2]
        endif
        let lclass = lclass + 1
    endwhile

    let lclass = a:ln
    let classNameL = []
    while 1
        let ff = matchlist(getline('.'), classPattern)
        if len(ff) > 2
            call insert(classNameL, ff[2])
        endif
        normal [{
        if line('.') < lclass
            let lclass = line('.')
        else
            exec "normal ".a:ln."G"
            break
        endif
    endwhile

    let className = mainClassName
    if len(classNameL) > 0
        let className = join(classNameL, '$')
    endif

    if len(packageName) > 1
        let mainClassName = packageName.".".mainClassName
        let className = packageName.".".className
    endif

    let pn = substitute(mainClassName, '\.', '/', "g").".java"
    let g:mapClassFile[mainClassName] = pos
    let g:mapClassFile[className] = pos
    let srcRoot = substitute(a:fn, pn, "", "")
    if index(g:sourcepaths, srcRoot) == -1
        call add(g:sourcepaths, srcRoot)
    endif

    return className
endfunction

if !exists('g:jdbExecutable')
    let g:jdbExecutable = 'jdb'
endif

function! StartJDB(port)
    let s:cursign = 10000 - tabpagenr()
    let cw = bufwinid('%')
    if &ft == 'java'
        if stridx(a:port, ':') == -1
            let g:jdbPort = 'localhost:'.a:port
        else
            let g:jdbPort = a:port
        endif
        let t:pid = g:jdbPort
        let g:jdbBuf = "[JDB] ".g:jdbPort.">"
        let jdb_cmd = g:jdbExecutable.' -attach '.g:jdbPort
        let l:outHandler = 's:JdbOutHandler'
        call <SID>GetClassNameFromFile(expand("%:p"), line("."))
    else
        let jdb_cmd = "gdb"
        let g:jdbBuf = "[GDB] ".a:port.">"
        let s:pidToAttach = a:port
        let l:outHandler = 's:GdbOutHandler'

        if executable("lldb")
            let jdb_cmd = "lldb"
            let b:dbgCmdDelBreakpoint = 'breakpoint delete '
            let l:outHandler = 's:LldbOutHandler'
            let g:jdbBuf = "[LLDB] ".a:port.">"
            if filereadable(a:port)
                " StartJDB /works/depot_tools/chromium/src/out/Debug/Chromium.app/Contents/MacOS/Chromium
                let g:jdbBuf = "[LLDB] 0>"
            else
                " StartJDB /works/depot_tools/chromium/src/out/Debug/9766
                let ff = matchlist(a:port, '\(.*/\)\(.*\)')
                if len(ff) > 0
                    let s:pidToAttach = ff[2]
                    let s:exeDir = ff[1]
                endif
            endif
        endif
    endif
    let g:jdbBuf = resolve($HOME).'/'.g:jdbBuf
    let l:errHandler = "s:DbgErrHandler"
    let l:exitHandler = "s:DbgExitHandler"
    if has('nvim')
        let s:jdbJob = jobstart(jdb_cmd, {"on_stdout": function('s:NeoWrap', [l:outHandler]), "on_stderr": function('s:NeoWrap', [ l:errHandler ]), "on_exit": function('s:NeoWrap', [ l:exitHandler ])})
        let t:dbgChannel = s:jdbJob
    else
        let s:jdbJob = job_start(jdb_cmd, {"out_cb": function(l:outHandler), "err_cb": function(l:errHandler), "exit_cb": function(l:exitHandler), "out_io": "buffer", "out_name": g:jdbBuf})
        let t:dbgChannel = job_getchannel(s:jdbJob)
    endif
    call <SID>NewConsole(g:jdbBuf, bufnr('%'), jdb_cmd)
    let s:Help = []
    let s:CaptureHelp = 1
    call s:Chansend(t:dbgChannel, "help\n")
    execute win_id2win(cw)."wincmd w"
    if &ft == 'java'
        call <SID>SetBreakpoints(t:dbgChannel)
    elseif filereadable(a:port)
        call s:Chansend(t:dbgChannel, "target create ".a:port."\n")
    elseif s:pidToAttach != ""
        if jdb_cmd == "gdb"
            " init s:exeDir
            call s:Chansend(t:dbgChannel, "info proc ".s:pidToAttach."\n")
        else
            call s:Chansend(t:dbgChannel, "attach ".s:pidToAttach."\n")
        endif
    endif
    call writefile([""], $HOME."/.jdb.vim.log")
endfunction
com! -nargs=1 -complete=dir StartJDB call StartJDB("<args>")

function! s:GetBreakPoints()
    let breakpoints = []
    let bufinfos = getbufinfo()
    for bufinfo in bufinfos
        if has_key(bufinfo, 'signs')
            let fn = bufinfo.name
            let signs = bufinfo.signs
            for s in signs
                if s.name == "breakpt"
                    let ln = s.lnum
                    call add(breakpoints, [fn, ln])
                endif
            endfor
        endif
    endfor
    return breakpoints
endfunction

function! s:SetBreakpoints(jdb_ch)
    for bp in <SID>GetBreakPoints()
        call s:Chansend(a:jdb_ch, "stop at ".<SID>GetClassNameFromFile(bp[0], bp[1]).":".bp[1]."\n")
    endfor
endfunction

function! QuitJDB()
    if exists("t:dbgChannel")
        let final = 1
        if &ft == 'java'
            call s:Chansend(t:dbgChannel, <SID>GetBufVar("dbgCmdResume")."\n")
            call s:Chansend(t:dbgChannel, <SID>GetBufVar("dbgCmdExit")."\n")
        else
            if t:pid == 0
                call s:Chansend(t:dbgChannel, <SID>GetBufVar("dbgCmdExit")."\n")
            else
                let final = 0
                call s:Chansend(t:dbgChannel, "process detach\n")
            endif
        endif
        if final == 1
            if has('nvim')
                call jobstop(t:dbgChannel)
            else
                call ch_close(t:dbgChannel)
            endif
            call <SID>OnQuitJDB()
            unlet t:dbgChannel
        endif
    endif
endfunction

if !exists('g:jdbPort')
    let g:jdbPort = "localhost:6789"
endif

function! s:Run()
    if <SID>IsAttached()
        " if ch_canread(t:dbgChannel) == 0
            " call job_stop(s:jdbJob, "int")
        " endif
        call <SID>SendDbgCmdInConsole(<SID>GetBufVar("dbgCmdResume")."\n")
    else
        call StartJDB(g:jdbPort)
    endif
endfunction

function! StepOver()
    call <SID>SendDbgCmdInConsole("next\n")
endfunction

function! StepInto()
    call <SID>SendDbgCmdInConsole("step\n")
endfunction

function! StepUp()
    call <SID>SendDbgCmdInConsole(<SID>GetBufVar("dbgCmdStepUp")."\n")
endfunction

let g:nextBreakPointId = 1000
function! ToggleBreakPoint(condition)
    let ln = line('.')
    let fn = expand('%:p')
    let bno = 0
    let signs = sign_getplaced('%', {'lnum': line('.')})[0].signs
    for s in signs
        if s.name == 'breakpt'
            let bno = s.id
            break
        endif
    endfor
    let s:dbgBpKey = expand("%:t").":".ln
    if bno == 0
        silent exec "sign place ".g:nextBreakPointId." name=breakpt line=".ln." file=".fn
        if &ft == 'java'
            call <SID>SendDbgCmd("stop at ".<SID>GetClassNameFromFile(fn, ln).":".ln."\n")
        else
            if a:condition != ""
                " call <SID>SendDbgCmd("breakpoint set -f ".expand("%:t")." -l ".ln." --condition '".a:condition."'\n")
                let condition = substitute(a:condition, '"', '\\"', 'g')
                call <SID>SendDbgCmd("breakpoint set -f ".expand("%:t")." -l ".ln." ".condition."\n")
            else
                call <SID>SendDbgCmd("b ".s:dbgBpKey."\n")
            endif
        endif
        let g:nextBreakPointId = g:nextBreakPointId + 1
    else
        silent exec "sign unplace ".bno." file=".fn
        if &ft == 'java'
            call <SID>SendDbgCmd(<SID>GetBufVar("dbgCmdDelBreakpoint").<SID>GetClassNameFromFile(fn, ln).":".ln."\n")
        else
            if has_key(s:dbGBreakPoints, s:dbgBpKey)
                call <SID>SendDbgCmd(<SID>GetBufVar("dbgCmdDelBreakpoint").s:dbGBreakPoints[s:dbgBpKey]."\n")
                call remove(s:dbGBreakPoints, s:dbgBpKey)
            endif
        endif
    endif
endfunction

function! ShowScriptVariables()
    echo s:
endfunction

function! YankClassNameFromeFile()
    let @v = <SID>GetClassNameFromFile(expand("%:p"), line("."))
    let @" = @v
    let @* = @v
    if exists('*RYank')
        call RYank()
    endif
endfunction

function! s:GetBufVar(var)
    let bn = exists("b:lordBuf") ? b:lordBuf : bufnr('%')
    return getbufvar(bn, a:var)
endfunction

function! DbgSetupKeyMap()
    nnoremap <buffer> <silent> <F1> :call <SID>ShowHelp()<CR>
    nnoremap <buffer> <silent> <F2> :call StepInto()<CR>
    nnoremap <buffer> <silent> <F3> :call StepOver()<CR>
    nnoremap <buffer> <silent> <F4> :call StepUp()<CR>
    nnoremap <buffer> <silent> <F5> :call <SID>Run()<CR>
    nnoremap <buffer> <silent> <F6> :call QuitJDB()<CR>
    nnoremap <buffer> <silent> <F7> :call <SID>SendDbgCmdInConsole(<SID>GetBufVar("dbgCmdWhere")."\n")<CR>
    nnoremap <buffer> <silent> <F10> :call ToggleBreakPoint('')<CR>
    command! -buffer -nargs=1 Bp :call ToggleBreakPoint(<f-args>)
    command! -buffer -nargs=1 Bpa :call <SID>SendDbgCmd("breakpoint set -a ".<f-args>."\n")
    vnoremap <buffer> E "vy:call <SID>SendDbgCmd(<SID>GetBufVar("dbgCmdEval").@v)<CR>
    vnoremap <buffer> P "vy:call <SID>SendDbgCmd(<SID>GetBufVar("dbgCmdVar").@v)<CR>
endfunction

if !hlexists('DbgCurrent')
  hi DbgCurrent term=reverse ctermfg=White ctermbg=Red gui=reverse
endif
if !hlexists('DbgBreakPt')
  hi DbgBreakPt term=reverse ctermfg=White ctermbg=Green gui=reverse
endif
sign define current text=->  texthl=DbgCurrent linehl=DbgCurrent
sign define breakpt text=B>  texthl=DbgBreakPt linehl=DbgBreakPt

function! s:ListBreakPoints()
  lgetexpr map(<SID>GetBreakPoints(), 'v:val[0] . ":" . v:val[1] . "::"')
  lfirst
  lopen
endfunction
nnoremap <silent> <leader>wb :call <SID>ListBreakPoints()<CR>
