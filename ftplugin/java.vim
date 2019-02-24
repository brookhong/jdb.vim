function! SearchFileBackwards(fn)
    let fp = expand('%:p')
    let pos = len(fp) - 1
    while pos > 0
        let pom = ""
        if fp[pos] == '/'
            let pom = strpart(fp, 0, pos + 1) . a:fn
            if filereadable(pom)
                break
            endif
        endif
        let pos = pos - 1
    endwhile
    return strpart(fp, 0, pos + 1)
endfunction

function! BuildMavenProject()
    let consoleName = "*quick build*"
    call FocusMyConsole("botri 10", consoleName)
    exe "normal \<C-W>w"
    let pom = SearchFileBackwards("pom.xml")
    if pom != "/"
        call job_start('mvn -f '.SearchFileBackwards("pom.xml").'pom.xml compile', {"out_io": "buffer", "out_name": consoleName, "err_io": "buffer", "err_name": consoleName})
    else
        let pom = SearchFileBackwards("build.xml")
        if pom != "/"
            call job_start(['sh', '-c', 'cd '.pom.' && brazil-build'], {"out_io": "buffer", "out_name": consoleName, "err_io": "buffer", "err_name": consoleName})
        else
            call job_start(['sh', '-c', 'javac '.expand('%').' && java -cp '.expand('%:h').' '.expand('%:r')], {"out_io": "buffer", "out_name": consoleName, "err_io": "buffer", "err_name": consoleName})
        endif
    endif
endfunction

" autocmd BufWritePost *.java :call BuildMavenProject()

function! RemoveUnusedJavaPackages()
    let lastLine = line('$')
    let currentLine = 1
    let codeLine = 1
    let classes = []
    while currentLine <= lastLine
        let line = getline(currentLine)
        let className = matchlist(line, '^\s*import\s\+\S*\.\([^.]\+\)\s*;')
        if len(className) > 1
            call add(classes, className[1])
            let codeLine = currentLine + 1
        endif
        let currentLine += 1
    endwhile

    normal mo
    let unusedClasses = []
    for class in classes
        call cursor(codeLine, 0)
        let r = '\<'.class.'\>'
        if !search(r, 'W')
            call add(unusedClasses, r)
        endif
    endfor
    normal 'o

    if len(unusedClasses)
        let @/ = 'import\s\+.*\('.join(unusedClasses, '\|').'\)\s*;'
        exec 'g/'.@/.'/d'
    else
        echo "All imported classes are in use."
    endif
endfunction
nnoremap <buffer> <silent> <C-C> :call RemoveUnusedJavaPackages()<CR>

nnoremap <buffer> <silent> <F2> :call StepInto()<CR>
nnoremap <buffer> <silent> <F3> :call StepOver()<CR>
nnoremap <buffer> <silent> <F4> :call StepUp()<CR>
nnoremap <buffer> <silent> <F5> :call Run()<CR>
nnoremap <buffer> <silent> <F6> :call QuitJDB()<CR>
nnoremap <buffer> <silent> <F7> :call ch_sendraw(t:jdb_ch, "where\n")<CR>
nnoremap <buffer> <silent> <F8> :call BuildMavenProject()<CR>
nnoremap <buffer> <silent> <F10> :call ToggleBreakPoint()<CR>
nnoremap <buffer> <silent> yc :call YankClassNameFromeFile()<CR>
command! -buffer -nargs=0 Bp :call ToggleBreakPoint()
command! -buffer -nargs=* J :call ch_sendraw(t:jdb_ch, <q-args>."\n")
vnoremap E "vy:call SendJDBCmd("eval ".@v)<CR>
