set title encoding=utf-8 fileformats=unix mouse=a ambiwidth=double
if exists('+termguicolors')
    set termguicolors
endif
set tabstop=2 softtabstop=2 shiftwidth=2 expandtab autoindent smartindent
set number cursorline showtabline=2 cmdheight=2 nowrap noerrorbells matchtime=0
if exists('+signcolumn')
    set signcolumn=yes
endif
set incsearch ignorecase smartcase hlsearch wrapscan showcmd wildmenu
set hidden nowritebackup nobackup noswapfile autoread
set ttimeout ttimeoutlen=50 timeoutlen=600 nrformats=
set whichwrap=h,l,<,>,[,],~
set virtualedit=block splitbelow splitright backspace=indent,eol,start
if has('persistent_undo')
    let s:cache_root = empty($XDG_CACHE_HOME) ? expand('~/.cache') : $XDG_CACHE_HOME
    let s:undo_dir = s:cache_root . '/revim-vim/undo'
    try
        call mkdir(s:undo_dir, 'p', 0700)
        let &undodir = escape(s:undo_dir, ',') . '//'
        set undofile
    catch
        set noundofile
        echomsg 'revim: persistent undo unavailable: ' . v:exception
    endtry
endif
filetype plugin indent on
syntax enable
