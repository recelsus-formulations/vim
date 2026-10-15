let s:pairs = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'", '`': '`'}

function! s:is_escaped(text) abort
    return strlen(matchstr(a:text, '\\*$')) % 2 == 1
endfunction

function! s:is_inside_quote(text, quote) abort
    let inside = 0
    let escaped = 0
    for character in split(a:text, '\zs')
        if character ==# a:quote && !escaped
            let inside = !inside
        endif
        let escaped = character ==# '\' && !escaped
    endfor
    return inside
endfunction

function! s:insert_character(character) abort
    if &buftype !=# '' || &paste
        return a:character
    endif
    let before = strpart(getline('.'), 0, col('.') - 1)
    let next = matchstr(strpart(getline('.'), col('.') - 1), '^.')
    let closing = get(s:pairs, a:character, '')
    let is_quote = closing ==# a:character
    if is_quote && s:is_escaped(before)
        return a:character
    endif
    if next ==# a:character && (is_quote || stridx(')]}', a:character) >= 0)
        return "\<C-g>U\<Right>"
    endif
    if empty(closing)
        return a:character
    endif
    if is_quote && (before =~# '[[:alnum:]_]$' || s:is_inside_quote(before, a:character))
        return a:character
    endif
    if !empty(next) && next !~# '[[:space:])\]},;:]'
        return a:character
    endif
    return a:character . closing . "\<C-g>U\<Left>"
endfunction

function! s:backspace() abort
    if &buftype !=# '' || &paste
        return "\<BS>"
    endif
    let before = strpart(getline('.'), 0, col('.') - 1)
    let previous = matchstr(before, '.$')
    let next = matchstr(strpart(getline('.'), col('.') - 1), '^.')
    if !empty(next) && get(s:pairs, previous, '') ==# next
        if previous !=# next || !s:is_escaped(strpart(before, 0, strlen(before) - 1))
            return "\<BS>\<Del>"
        endif
    endif
    return "\<BS>"
endfunction

for s:character in keys(s:pairs) + [')', ']', '}']
    execute 'inoremap <silent> ' . s:character
                \ . ' <C-R>=<SID>insert_character(' . string(s:character) . ')<CR>'
endfor
inoremap <silent> <BS> <C-R>=<SID>backspace()<CR>
