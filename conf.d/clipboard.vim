let s:registers = get(s:, 'registers', {})

function! s:encode(text) abort
    let alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let encoded = ''
    let index = 0
    while index < strlen(a:text)
        let byte_count = min([3, strlen(a:text) - index])
        let bytes = []
        for offset in range(3)
            call add(bytes, offset < byte_count ? char2nr(strpart(a:text, index + offset, 1)) : 0)
        endfor
        let value = bytes[0] * 65536 + bytes[1] * 256 + bytes[2]
        let encoded .= alphabet[value / 262144 % 64] . alphabet[value / 4096 % 64]
                    \ . (byte_count > 1 ? alphabet[value / 64 % 64] : '=')
                    \ . (byte_count > 2 ? alphabet[value % 64] : '=')
        let index += 3
    endwhile
    return encoded
endfunction

function! RevimClipboardCopy(register, type, lines) abort
    let s:registers[a:register] = [a:type, copy(a:lines)]
    if exists('*echoraw') && has('ttyout') && !has('gui_running')
        let text = join(a:lines, "\n") . (a:type ==# 'V' ? "\n" : '')
        let selection = a:register ==# '*' ? 'p' : 'c'
        call echoraw("\e]52;" . selection . ';' . s:encode(text) . "\x07")
    endif
endfunction

function! RevimClipboardPaste(register) abort
    let cached = deepcopy(get(s:registers, a:register, ['v', ['']]))
    let command = get(g:revim_environment, 'paste_command', [])
    if !get(g:, 'revim_clipboard_external_paste', 0) || empty(command) || !has('job')
        return cached
    endif
    let directory = tempname()
    let job = v:null
    try
        call mkdir(directory, 'p', 0700)
        let output = directory . '/clipboard'
        let job = job_start(command, {'in_io': 'null', 'out_io': 'file', 'out_name': output, 'err_io': 'null'})
        let started = reltime()
        while job_status(job) ==# 'run' && reltimefloat(reltime(started)) < 2.0
            sleep 10m
        endwhile
        if job_status(job) !=# 'dead' || get(job_info(job), 'exitval', -1) != 0
            return cached
        endif
        let text = join(readfile(output, 'b'), "\n")
        let text = substitute(substitute(text, "\r\n", "\n", 'g'), "\r", "\n", 'g')
        let copied = join(cached[1], "\n")
        if has_key(s:registers, a:register)
                    \ && (text ==# copied || (cached[0] ==# 'V' && text ==# copied . "\n"))
            return cached
        endif
        let linewise = text =~# "\n$"
        if linewise
            let text = strpart(text, 0, strlen(text) - 1)
        endif
        let s:registers[a:register] = [linewise ? 'V' : 'v', split(text, "\n", 1)]
        return deepcopy(s:registers[a:register])
    catch
        return cached
    finally
        if job isnot v:null && job_status(job) ==# 'run'
            call job_stop(job, 'kill')
        endif
        call delete(directory, 'rf')
    endtry
endfunction

function! s:yank() abort
    if index(['', '+', '*'], v:event.regname) >= 0
        call RevimClipboardCopy(v:event.regname ==# '*' ? '*' : '+', v:event.regtype, v:event.regcontents)
    endif
endfunction

function! s:put(motion) abort
    if index(['"', '+', '*'], v:register) < 0
        return a:motion
    endif
    let register = v:register ==# '*' ? '*' : '+'
    let value = RevimClipboardPaste(register)
    call setreg('"', value[1], value[0])
    return '""' . a:motion
endfunction

if exists('v:clipproviders') && exists('+clipmethod')
    let v:clipproviders.revim_osc52 = {
                \ 'copy': {'+': function('RevimClipboardCopy'), '*': function('RevimClipboardCopy')},
                \ 'paste': {'+': function('RevimClipboardPaste'), '*': function('RevimClipboardPaste')}}
    set clipmethod=revim_osc52
    set clipboard=unnamedplus
else
    set clipboard-=unnamed clipboard-=unnamedplus
    augroup revim_clipboard
        autocmd!
        autocmd TextYankPost * call <SID>yank()
    augroup END
    for s:motion in ['p', 'P', 'gp', 'gP']
        for s:mode in ['n', 'x']
            execute s:mode . 'noremap <silent><expr> ' . s:motion
                        \ . ' <SID>put(' . string(s:motion) . ')'
        endfor
    endfor
endif
