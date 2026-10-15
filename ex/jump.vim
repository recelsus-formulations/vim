function! s:jump() abort
    if &buftype !=# '' || !exists('*popup_create') || !exists('*screenpos')
        echo 'revim: jump labels require Vim popup windows and screenpos()'
        return
    endif
    let targets = []
    let current = getpos('.')
    redraw
    for number in range(line('w0'), line('w$'))
        if foldclosed(number) >= 0
            continue
        endif
        let text = getline(number)
        let start = 0
        while start < strlen(text)
            let word = matchstrpos(text, '\k\+', start)
            let column = word[1]
            if column < 0
                break
            endif
            let start = word[2]
            let position = screenpos(win_getid(), number, column + 1)
            if position.row > 0 && position.col > 0
                        \ && (number != current[1] || column + 1 != current[2])
                call add(targets, {'line': number, 'column': column + 1, 'screen': position,
                            \ 'distance': abs(number - current[1]) * winwidth(0)
                            \ + abs(column + 1 - current[2])})
            endif
        endwhile
    endfor
    if empty(targets)
        return
    endif
    call sort(targets, {left, right -> left.distance - right.distance})
    let width = 1
    while pow(26, width) < len(targets)
        let width += 1
    endwhile
    for index in range(len(targets))
        let value = index
        let label = ''
        for digit in range(width)
            let label = nr2char(char2nr('a') + value % 26) . label
            let value = value / 26
        endfor
        let targets[index].label = label
    endfor
    let popups = []
    let prefix = ''
    try
        while !empty(targets)
            if len(targets) == 1
                normal! m'
                call cursor(targets[0].line, targets[0].column)
                return
            endif
            for target in targets
                call add(popups, popup_create(strpart(target.label, strlen(prefix)), {
                            \ 'line': target.screen.row, 'col': target.screen.col,
                            \ 'highlight': 'ExJumpLabel', 'wrap': 0, 'zindex': 200,
                            \ 'mapping': 0, 'padding': [0, 0, 0, 0]}))
            endfor
            redraw
            let key = tolower(getcharstr())
            for popup in popups
                call popup_close(popup)
            endfor
            let popups = []
            if key !~# '^[a-z]$'
                return
            endif
            let prefix .= key
            call filter(targets, 'stridx(v:val.label, prefix) == 0')
        endwhile
    catch /^Vim:Interrupt$/
        " Cancellation leaves the original position unchanged.
    finally
        for popup in popups
            call popup_close(popup)
        endfor
    endtry
endfunction

highlight default ExJumpLabel ctermfg=0 ctermbg=220 cterm=bold guifg=#000000 guibg=#ffd700 gui=bold
nnoremap <silent> <C-f> :call <SID>jump()<CR>
augroup revim_jump
    autocmd!
    autocmd ColorScheme * highlight default ExJumpLabel ctermfg=0 ctermbg=220 cterm=bold
                \ guifg=#000000 guibg=#ffd700 gui=bold
augroup END
