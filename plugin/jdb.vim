function! s:ParseStackFile()
    let ff = matchlist(getline("."), '  \[\d\+\] \(\S\+\)\.\(\S\+\) (\(\S\+\).java:\(\d\+\))')
    if len(ff) > 0
        call <SID>SetCursor(substitute(ff[1], '\.\a\+$' , '.'.ff[3], ''), ff[4])
        exe "normal \<C-W>w"
        call <SID>HitBreakPoint("")
        exe "normal \<C-W>w"
        return 1
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
        let t:bpFile = g:mapClassFile[l:mainClassName]
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

function! s:HitBreakPoint(str)
    if !exists("t:bpFile")
        return 0
    endif
    for dir in g:sourcepaths
        if filereadable(dir.t:bpFile)
            let fl = readfile(dir.t:bpFile)
            if len(fl) > t:bpLine && (a:str == "" || stridx(a:str, fl[t:bpLine - 1]) > 0)
                if bufname('%') =~ '^\[JDB\]'
                    exe "normal \<C-W>w"
                endif
                let t:bpFile = dir.t:bpFile
                silent exec "sign unplace ".t:cursign
                silent exec "edit ".t:bpFile
                silent exec 'sign place '.t:cursign.' name=current line='.t:bpLine.' file='.t:bpFile
                exec t:bpLine
                redraw!
                unlet t:bpFile
                return 1
            endif
        end
    endfor
    return 0
endfunction

function! s:NothingSuspended(str)
    if a:str == "> Nothing suspended." || a:str =~ '^\S\+ All threads resume.'
        silent exec "sign unplace ".t:cursign
        call <SID>PlaceBreakSigns()
        return 1
    endif
    return 0
endfunction

function! JdbErrHandler(channel, msg)
    echo a:msg
endfunction

function! JdbExitHandler(channel, msg)
    call OnQuitJDB()
endfunction

function! JdbOutHandler(channel, msg)
    call writefile([a:msg], $HOME."/.jdb.vim.log", "a")
    if !<SID>GetBreakPointHit(a:msg) && !<SID>HitBreakPoint(a:msg) && !<SID>NothingSuspended(a:msg)
        echo a:msg
    endif
endfunction

let g:sourcepaths = [""]
let g:mapClassFile = {}
let g:mapFileClass = {}
function! s:GetClassNameFromFile(fn, ln)
    if has_key(g:mapFileClass, a:fn.':'.a:ln)
        return g:mapFileClass[a:fn.':'.a:ln]
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
    let classPattern = '^\s*\%(public\s\+\)\?\%(final\s\+\)\?\%(abstract\s\+\)\?\(class\|interface\)\s\+\(\w\+\)'
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
    let g:mapClassFile[mainClassName] = a:fn
    let srcRoot = substitute(a:fn, pn, "", "")
    if index(g:sourcepaths, srcRoot) == -1
        call add(g:sourcepaths, srcRoot)
    endif

    let g:mapFileClass[a:fn.':'.a:ln] = className
    return className
endfunction

if !exists('g:jdbExecutable')
    let g:jdbExecutable = 'jdb'
endif

function! s:InitJavaTab()
    if !exists('t:breakpoints')
        let t:breakpoints = {}
        let t:nextBreakPointId = 10000
    endif
endfunction

function! StartJDB(port)
    let t:cursign = 10000 - tabpagenr()
    let t:jdb_buf = "[JDB] ".a:port.">"
    call <SID>GetClassNameFromFile(expand("%:p"), line("."))
    let cw = bufwinnr('%')
    let jdb_cmd = g:jdbExecutable.' -sourcepath '.join(g:sourcepaths, ":").' -attach '.a:port
    call FocusMyConsole("botri 10", t:jdb_buf)
    call append(".", jdb_cmd)
    execute cw."wincmd w"
    let t:jdb_job = job_start(jdb_cmd, {"out_cb": "JdbOutHandler", "err_cb": "JdbErrHandler", "exit_cb": "JdbExitHandler", "out_io": "buffer", "out_name": t:jdb_buf})
    let t:jdb_ch = job_getchannel(t:jdb_job)
    call <SID>PlaceBreakSigns()
    call writefile([""], $HOME."/.jdb.vim.log")
endfunction

function! s:PlaceBreakSigns()
    for pos in keys(t:breakpoints)
        if t:breakpoints[pos][1]
            let bno = t:breakpoints[pos][0]
            let ff = matchlist(pos, '\([^:]\+\):\(\d\+\)')
            let fn = ff[1]
            let ln = ff[2]
            silent exec "sign place ".bno." name=breakpt line=".ln." file=".fn
            call ch_sendraw(t:jdb_ch, "stop at ".<SID>GetClassNameFromFile(fn, ln).":".ln."\n")
        endif
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
        call ch_sendraw(t:jdb_ch, "resume\n")
        call ch_sendraw(t:jdb_ch, "exit\n")
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
        call ch_sendraw(t:jdb_ch, a:cmd."\n")
    endif
endfunction

if !exists('g:jdbPort')
    let g:jdbPort = "localhost:6789"
endif

function! Run()
    if IsAttached()
        call ch_sendraw(t:jdb_ch, "resume\n")
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
    call ch_sendraw(t:jdb_ch, "step up\n")
endfunction

function! GetBreakPointId(pos)
    call <SID>InitJavaTab()
    if has_key(t:breakpoints, a:pos)
        return t:breakpoints[a:pos]
    else
        let t:breakpoints[a:pos] = t:nextBreakPointId
        let t:nextBreakPointId = t:nextBreakPointId + 1
        return [t:breakpoints[a:pos], 0]
    endif
endfunction

function! GetVisualSelection()
  let [lnum1, col1] = getpos("'<")[1:2]
  let [lnum2, col2] = getpos("'>")[1:2]
  let lines = getline(lnum1, lnum2)
  let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
  let lines[0] = lines[0][col1 - 1:]
  return join(lines, "\n")
endfunction

function! ToggleBreakPoint()
    let ln = line('.')
    let fn = expand('%:p')
    let pos = fn.":".ln
    let [bno, enabled] = GetBreakPointId(pos)
    if enabled
        silent exec "sign unplace ".bno." file=".fn
        call SendJDBCmd("clear ".<SID>GetClassNameFromFile(fn, ln).":".ln)
        let t:breakpoints[pos] = [bno, 0]
    else
        silent exec "sign place ".bno." name=breakpt line=".ln." file=".fn
        call SendJDBCmd("stop at ".<SID>GetClassNameFromFile(fn, ln).":".ln)
        let t:breakpoints[pos] = [bno, 1]
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
