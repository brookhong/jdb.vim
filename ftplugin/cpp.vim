nnoremap <buffer> <silent> <F2> :call StepInto()<CR>
nnoremap <buffer> <silent> <F3> :call StepOver()<CR>
nnoremap <buffer> <silent> <F4> :call StepUp()<CR>
nnoremap <buffer> <silent> <F5> :call Run()<CR>
nnoremap <buffer> <silent> <F6> :call QuitJDB()<CR>
nnoremap <buffer> <silent> <F7> :call ch_sendraw(t:jdb_ch, "where\n")<CR>
nnoremap <buffer> <silent> <F10> :call ToggleBreakPoint()<CR>
command! -buffer -nargs=0 Bp :call ToggleBreakPoint()
command! -buffer -nargs=* J :call ch_sendraw(t:jdb_ch, <q-args>."\n")
vnoremap E "vy:call SendJDBCmd("p ".@v)<CR>
