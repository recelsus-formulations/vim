set nocompatible
set noloadplugins
let s:config_root = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let &runtimepath = escape(s:config_root, ',\') . ',' . escape($VIMRUNTIME, ',\')
let &packpath = &runtimepath
let mapleader = ' '

for s:setting in ['environment', 'clipboard']
    execute 'source ' . fnameescape(s:config_root . '/conf.d/' . s:setting . '.vim')
endfor
unlet s:setting
execute 'source ' . fnameescape(s:config_root . '/config.vim')
colorscheme slate
execute 'source ' . fnameescape(s:config_root . '/conf.d/display.vim')
for s:feature in ['tree', 'term', 'pairs', 'jump', 'scope', 'signs', 'find']
    execute 'source ' . fnameescape(s:config_root . '/ex/' . s:feature . '.vim')
endfor
unlet s:feature
