function! s:OnEnter()
    if exists("t:dbgChannel") && t:pid != 0
        let qfName = getloclist(0, {'title':0}).title
        if qfName == 'Call Stack'
            call ch_sendraw(t:dbgChannel, 'f '.(line('.')-1)."\n")
        elseif qfName == 'JVM Call Stack'
            call SetJVMFrame(line('.'))
        endif
        call setloclist(0, [], 'r', { 'idx': line('.') })
    else
        exec ':ll '.line('.')
    endif
endfunction
nnoremap <silent> <buffer> <CR> :call <SID>OnEnter()<cr>

function! s:OnDiff()
    let hash = substitute(getline('.'), ':.*', '','')
    lclose
    exec 'Gvdiffsplit '.hash
endfunction
nnoremap <silent> <buffer> D :call <SID>OnDiff()<cr>
