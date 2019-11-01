function! s:ParseStackFile()
    let ff = matchlist(getline("."), '  \[\d\+\] \(\S\+\)\.\(\S\+\) (\(\S\+\).java:\(\d\+\))')
    if len(ff) > 0
        call <SID>SetCursor(substitute(ff[1], '\.\a\+$' , '.'.ff[3], ''), ff[4])
        exe "normal \<C-W>w"
        call <SID>HitBreakPoint("")
        exe "normal \<C-W>w"
        return 1
    endif

    let ff = matchlist(getline("."), '^#\(\d\+\)\s\+0x\w\+\> in ')
    if len(ff) > 0
        call ch_sendraw(t:jdb_ch, "frame ".ff[1]."\n")
        return 1
    endif

    if exists("t:exeDir")
        let ff = matchlist(getline("."), '.* at \([^:]\+\):\(\d\+\)')
        if len(ff) > 0
            let t:bpFile = t:exeDir.ff[1]
            let t:bpLine = ff[2]
            call <SID>PlaceCursor()
            return 1
        endif
    endif
    return 0
endfunction

function! s:ConsoleOnEnter()
    if !<SID>ParseStackFile()
        call ch_sendraw(t:jdb_ch, getline(".")."\n")
    endif
endfunction

function! FocusMyConsole(winOp, bufName)
    let bn = bufwinnr(a:bufName)
    if bn == -1
        execute "silent ".a:winOp." new ".a:bufName
        setlocal enc=utf-8
        setlocal buftype=nofile
        setlocal nobuflisted
        setlocal noswapfile
        setlocal noreadonly
        setlocal ff=unix
        setlocal nolist
        map <buffer> q :q<CR>
        map <buffer> <CR> :call <SID>ConsoleOnEnter()<CR>
    else
        execute bn."wincmd w"
    endif
endfunction

function! s:SetCursor(className, lineNo)
    let l:mainClassName = substitute(a:className, '\$.*', '', '')
    if has_key(g:mapClassFile, l:mainClassName)
        let t:bpFile = substitute(g:mapClassFile[l:mainClassName], ':.*', '', '')
    else
        let t:bpFile = substitute(l:mainClassName, '\.', '/', 'g').".java"
    endif
    let t:bpLine = a:lineNo
endfunction

function! s:GetBreakPointHit(str)
    let ff = matchlist(a:str, '\(Step completed: \|Breakpoint hit: \|\)"thread=\([^"]\+\)", \(\S\+\)\.\(\S\+\)(), line=\([0-9,]\+\) bci=\(\d\+\)')
    if len(ff) > 0
        call <SID>SetCursor(ff[3], substitute(ff[5], ",", '', 'g'))
        return 1
    endif
    return 0
endfunction

function! s:PlaceCursor()
    if bufname('%') =~ '^\[JDB\]'
        exe "normal \<C-W>w"
    endif
    silent exec "sign unplace ".t:cursign
    silent exec "edit ".t:bpFile
    silent exec 'sign place '.t:cursign.' name=current line='.t:bpLine.' file='.t:bpFile
    exec t:bpLine
    redraw!
endfunction

function! s:HitBreakPoint(str)
    if !exists("t:bpFile")
        return 0
    endif
    for dir in g:sourcepaths
        if filereadable(dir.t:bpFile)
            let fl = readfile(dir.t:bpFile)
            if len(fl) > t:bpLine && (a:str == "" || stridx(a:str, fl[t:bpLine - 1]) > 0)
                let t:bpFile = dir.t:bpFile
                call <SID>PlaceCursor()
                if &ft == 'java'
                    unlet t:bpFile
                endif
                return 1
            endif
        end
    endfor
    return 0
endfunction

function! s:NothingSuspended(str)
    if a:str == "> Nothing suspended." || a:str =~ '^\S\+ All threads resume.'
        silent exec "sign unplace ".t:cursign
        return 1
    endif
    return 0
endfunction

function! s:UnableToSetBreakpoint(str)
    let ff = matchlist(a:str,  '^.* Unable to set breakpoint \([^:]\+\):\(\d\+\) : No code at line \2 in \1$')
    if len(ff)
        call SendJDBCmd("clear ".ff[1].":".ff[2])
        " try to set breakpoints for nested classes if current class is an outer one
        if stridx(ff[1], '$') == -1
            call SendJDBCmd("class ".ff[1])
            let t:breakptOuterClass = ff[1]
            let t:breakptInNestedClass = ff[2]
        elseif has_key(g:mapClassFile, ff[1])
            call remove(g:mapClassFile, ff[1])
        endif
        return 1
    endif
    return 0
endfunction

function! s:SetBreakpointInNestedClass(str)
    let ff = matchlist(a:str,  '^nested: \(\S\+\)$')
    if len(ff) && exists('t:breakptInNestedClass')
        call SendJDBCmd("stop at ".ff[1].":".t:breakptInNestedClass)
        let g:mapClassFile[ff[1]] = g:mapClassFile[substitute(ff[1], '\$.*', '', '')]
        return 1
    endif
    return 0
endfunction

function! s:OnBreakPointSetInNestedClass(str)
    if exists('t:breakptInNestedClass')
        let ff = matchlist(a:str, '^> Set breakpoint '.t:breakptOuterClass.'$1:'.t:breakptInNestedClass.'$')
        if len(ff)
            unlet t:breakptOuterClass
            unlet t:breakptInNestedClass
            return 1
        endif
        return 0
    endif
endfunction

function! JdbErrHandler(channel, msg)
    call writefile(['[E] '.a:msg], $HOME."/.jdb.vim.log", "a")
    echo a:msg
endfunction

function! JdbExitHandler(channel, msg)
    call OnQuitJDB()
endfunction

function! JdbOutHandler(channel, msg)
    call writefile([a:msg], $HOME."/.jdb.vim.log", "a")
    if !<SID>GetBreakPointHit(a:msg) && !<SID>HitBreakPoint(a:msg) && !<SID>NothingSuspended(a:msg) && !<SID>UnableToSetBreakpoint(a:msg) && !<SID>SetBreakpointInNestedClass(a:msg) && !<SID>OnBreakPointSetInNestedClass(a:msg)
        echo a:msg
    endif
endfunction

let g:gdbBreakPoints = {}
function! GdbOutHandler(channel, msg)
    call writefile([a:msg], $HOME."/.jdb.vim.log", "a")

    let ff = matchlist(a:msg, '^(gdb) Breakpoint \(\d\+\) at 0x\w\+: file .*/\([^,]\+\), line \(\d\+\).$')
    if len(ff)
        let g:gdbBreakPoints[ff[2].':'.ff[3]] = ff[1]
        return
    endif

    let ff = matchlist(a:msg, "exe = '\\([^']\\+\\)'")
    if len(ff) > 0
        let t:exeDir = substitute(ff[1], '/[^/]\+$', '/', '')
        call ch_sendraw(t:jdb_ch, "cd ".t:exeDir."\n")
        call ch_sendraw(t:jdb_ch, "attach ".s:pidToAttach."\n")
        for bp in <SID>GetBreakPoints()
            call ch_sendraw(t:jdb_ch, "break ".substitute(bp[0], '.*/', '', '').":".bp[1]."\n")
        endfor
        return
    endif

    if exists("t:exeDir")
        " let ff = matchlist(a:msg, '^\(\((gdb) \)\?#\d\+\)\@!\S.* at \([^:]\+\):\(\d\+\)')
        let ff = matchlist(a:msg, 'Thread \d\+ ".*" hit Breakpoint \d\+, .* at \([^:]\+\):\(\d\+\)')
        if len(ff) == 0
            " let ff = matchlist(a:msg, '^(gdb) #\d\+\s\+0x\w\+\> in .* at \([^:]\+\):\(\d\+\)')
            let ff = matchlist(a:msg, '^(gdb) .* at \([^:]\+\):\(\d\+\)')
        endif
        if len(ff) > 0
            let t:bpFile = t:exeDir.ff[1]
            let t:bpLine = ff[2]
            call <SID>PlaceCursor()
            return
        endif
    endif

    let ff = matchlist(a:msg, '(gdb) \(\d\+\)\t.*')
    if len(ff) > 0
        let t:bpLine = ff[1]
        call <SID>PlaceCursor()
        return
    endif

    if a:msg == '(gdb) Continuing.'
        silent exec "sign unplace ".t:cursign
        return
    endif

    call writefile(["***UNHANDLED***"], $HOME."/.jdb.vim.log", "a")
endfunction

let g:sourcepaths = [""]
let g:mapClassFile = {}
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
    let t:cursign = 10000 - tabpagenr()
    let t:jdb_buf = "[JDB] ".a:port.">"
    let cw = bufwinnr('%')
    let jdb_cmd = g:jdbExecutable.' -sourcepath '.join(g:sourcepaths, ":").' -attach '.a:port
    let s:cmdResume = 'resume'
    let s:cmdExit = 'exit'
    let s:cmdStepUp = 'step up'
    let l:outHandler = 'JdbOutHandler'
    if &ft == 'java'
        call <SID>GetClassNameFromFile(expand("%:p"), line("."))
    else
        let jdb_cmd = "gdb"
        let s:pidToAttach = a:port
        let s:cmdResume = 'continue'
        let s:cmdExit = 'quit'
        let s:cmdStepUp = 'finish'
        let l:outHandler = 'GdbOutHandler'
    endif
    call FocusMyConsole("botri 10", t:jdb_buf)
    call append(".", jdb_cmd)
    normal ggddG
    execute cw."wincmd w"
    let t:jdb_job = job_start(jdb_cmd, {"out_cb": l:outHandler, "err_cb": "JdbErrHandler", "exit_cb": "JdbExitHandler", "out_io": "buffer", "out_name": t:jdb_buf})
    let t:jdb_ch = job_getchannel(t:jdb_job)
    if &ft == 'java'
        call <SID>SetBreakpoints(t:jdb_ch)
    else
        " init t:exeDir
        call ch_sendraw(t:jdb_ch, "info proc ".s:pidToAttach."\n")
    endif
    call writefile([""], $HOME."/.jdb.vim.log")
endfunction
com! -nargs=1 StartJDB call StartJDB("<args>")

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
        call ch_sendraw(a:jdb_ch, "stop at ".<SID>GetClassNameFromFile(bp[0], bp[1]).":".bp[1]."\n")
    endfor
endfunction

function! OnQuitJDB()
    silent exec "sign unplace ".t:cursign
    if exists("t:jdb_buf")
        call FocusMyConsole("botri 10", t:jdb_buf)
        q
        unlet t:jdb_buf
    endif
endfunction

function! QuitJDB()
    if exists("t:jdb_ch")
        if &ft == 'java'
            call ch_sendraw(t:jdb_ch, s:cmdResume."\n")
            call ch_sendraw(t:jdb_ch, s:cmdExit."\n")
        else
            call ch_sendraw(t:jdb_ch, s:cmdExit."\n")
        endif
        call ch_close(t:jdb_ch)
        call OnQuitJDB()
        unlet t:jdb_ch
    endif
endfunction

function! IsAttached()
    return exists("t:jdb_ch") && ch_status(t:jdb_ch) == "open"
endfunction

function! SendJDBCmd(cmd)
    if IsAttached()
        if &ft == 'java'
            call ch_sendraw(t:jdb_ch, a:cmd."\n")
        else
            if ch_canread(t:jdb_ch) == 0
                call job_stop(t:jdb_job, "int")
            endif
            call ch_sendraw(t:jdb_ch, a:cmd."\n")
        endif
    endif
endfunction

if !exists('g:jdbPort')
    let g:jdbPort = "localhost:6789"
endif

function! Run()
    if IsAttached()
        call ch_sendraw(t:jdb_ch, s:cmdResume."\n")
    else
        call StartJDB(g:jdbPort)
    endif
endfunction

function! StepOver()
    call ch_sendraw(t:jdb_ch, "next\n")
endfunction

function! StepInto()
    call ch_sendraw(t:jdb_ch, "step\n")
endfunction

function! StepUp()
    call ch_sendraw(t:jdb_ch, s:cmdStepUp."\n")
endfunction

function! GetVisualSelection()
  let [lnum1, col1] = getpos("'<")[1:2]
  let [lnum2, col2] = getpos("'>")[1:2]
  let lines = getline(lnum1, lnum2)
  let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
  let lines[0] = lines[0][col1 - 1:]
  return join(lines, "\n")
endfunction

let g:nextBreakPointId = 1000
function! ToggleBreakPoint()
    let ln = line('.')
    let fn = expand('%:p')
    let bno = 0
    let bufinfo = getbufinfo('%')[0]
    if has_key(bufinfo, 'signs')
        let signs = bufinfo.signs
        for s in signs
            if s.lnum == ln
                let bno = s.id
                break
            endif
        endfor
    endif
    let gdbBpKey = expand("%").":".ln
    if bno == 0
        silent exec "sign place ".g:nextBreakPointId." name=breakpt line=".ln." file=".fn
        if &ft == 'java'
            call SendJDBCmd("stop at ".<SID>GetClassNameFromFile(fn, ln).":".ln)
        else
            call SendJDBCmd("b ".gdbBpKey)
        endif
        let g:nextBreakPointId = g:nextBreakPointId + 1
    else
        silent exec "sign unplace ".bno." file=".fn
        if &ft == 'java'
            call SendJDBCmd("clear ".<SID>GetClassNameFromFile(fn, ln).":".ln)
        else
            if has_key(g:gdbBreakPoints, gdbBpKey)
                call SendJDBCmd("delete ".g:gdbBreakPoints[gdbBpKey])
                call remove(g:gdbBreakPoints, gdbBpKey)
            endif
        endif
    endif
endfunction

function! YankClassNameFromeFile()
    let @v = <SID>GetClassNameFromFile(expand("%:p"), line("."))
    let @" = @v
    let @* = @v
    if exists('*RYank')
        call RYank()
    endif
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
