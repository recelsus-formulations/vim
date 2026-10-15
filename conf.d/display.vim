function! RevimRestoreWindow() abort
    for option in ['number', 'relativenumber', 'signcolumn', 'foldcolumn', 'wrap', 'cursorline', 'winfixwidth']
        execute 'let &l:' . option . ' = &g:' . option
    endfor
    unlet! w:revim_special
endfunction

function! RevimSpecialWindow() abort
    let w:revim_special = 1
    setlocal nonumber norelativenumber signcolumn=no foldcolumn=0 nowrap nowinfixwidth
endfunction

augroup revim_display
    autocmd!
    autocmd BufWinEnter * if get(w:, 'revim_special', 0) && &buftype ==# ''
                \ && !isdirectory(expand('%:p')) | call RevimRestoreWindow() | endif
augroup END
