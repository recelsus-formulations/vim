let s:active = get(s:, 'active', {})

function! s:clear() abort
    if !empty(s:active) && win_id2tabwin(s:active.window)[0] > 0
        for match in s:active.matches
            silent! call matchdelete(match, s:active.window)
        endfor
    endif
    let s:active = {}
endfunction

function! s:positions(text, column, direction, count) abort
    let characters = []
    let column = 1
    let cursor_index = 0
    for character in split(a:text, '\zs')
        call add(characters, {'text': character, 'column': column, 'keyword': character =~# '\k'})
        if column <= a:column
            let cursor_index = len(characters) - 1
        endif
        let column += strlen(character)
    endfor
    let primary = []
    let secondary = []
    let occurrences = {}
    let current_word = get(get(characters, cursor_index, {}), 'keyword', 0)
    let first = 0
    let second = 0
    let index = cursor_index + a:direction
    while index >= 0 && index < len(characters)
        let character = characters[index]
        if !character.keyword
            if !current_word
                if first > 0
                    call add(primary, first)
                elseif second > 0
                    call add(secondary, second)
                endif
            endif
            let current_word = 0
            let first = 0
            let second = 0
        elseif character.text =~# '^[A-Za-z0-9]$'
            let occurrence = get(occurrences, character.text, 0) + 1
            let occurrences[character.text] = occurrence
            if !current_word
                if occurrence == a:count && (first == 0 || a:direction == -1)
                    let first = character.column
                elseif occurrence == a:count + 1 && (second == 0 || a:direction == -1)
                    let second = character.column
                endif
            endif
        endif
        let index += a:direction
    endwhile
    if !current_word
        if first > 0
            call add(primary, first)
        elseif second > 0
            call add(secondary, second)
        endif
    endif
    return [primary, secondary]
endfunction

function! s:show(motion) abort
    call s:clear()
    if &buftype !=# '' || strlen(getline('.')) > 1000 || foldclosed('.') >= 0
        return a:motion
    endif
    let direction = a:motion ==# 'f' || a:motion ==# 't' ? 1 : -1
    let positions = s:positions(getline('.'), col('.'), direction, v:count1)
    let s:active = {'window': win_getid(), 'matches': []}
    for index in [0, 1]
        let group = index == 0 ? 'ExScopePrimary' : 'ExScopeSecondary'
        let entries = map(copy(positions[index]), '[line("."), v:val, 1]')
        while !empty(entries)
            call add(s:active.matches, matchaddpos(group, remove(entries, 0, min([7, len(entries) - 1])), 20))
        endwhile
    endfor
    redraw
    return a:motion
endfunction

function! s:colours() abort
    highlight default ExScopePrimary ctermfg=155 cterm=bold guifg=#afff5f gui=bold
    highlight default ExScopeSecondary ctermfg=81 cterm=bold guifg=#5fffff gui=bold
endfunction

for s:motion in ['f', 'F', 't', 'T']
    for s:mode in ['n', 'x', 'o']
        execute s:mode . 'noremap <silent><expr> ' . s:motion . ' <SID>show(' . string(s:motion) . ')'
    endfor
endfor
call s:colours()
augroup revim_scope
    autocmd!
    autocmd CursorMoved,BufLeave,WinLeave * call <SID>clear()
    if exists('##SafeState')
        autocmd SafeState * call <SID>clear()
    endif
    if exists('##ModeChanged')
        autocmd ModeChanged * call <SID>clear()
    endif
    autocmd ColorScheme * call <SID>clear() | call <SID>colours()
augroup END
