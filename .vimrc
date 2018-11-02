" Load Pathogen for easy Vim modules installation
execute pathogen#infect()
call pathogen#helptags()

set nocompatible              " be iMproved, required
filetype off                  " required

" Attempt to determine the type of a file based on its name and possibly its
" contents. Use this to allow intelligent auto-indenting for each filetype,
" and for plugins that are filetype specific.
filetype indent plugin on

" Enable syntax highlighting
syntax on

" Default enable the solarized color scheme
syntax enable
if has('gui_running')
  set transparency=3
endif
set background=dark
let g:solarized_termcolors=256
let g:solarized_termtrans=1
" let g:hybrid_use_Xresources = 1
" let g:rehash256 = 1
colorscheme solarized
set guifont=Inconsolata:h15
set guioptions-=L
" Change color of line numbers to grey
"highlight LineNr ctermfg=grey ctermbg=black guibg=black guifg=grey

set noerrorbells                " No beeps
set noshowmode                  " We show the mode with airline or lightline
set showcmd                     " Show partial commands in the last line of the screen
set splitright                  " Split vertical windows right to the current windows
set splitbelow                  " Split horizontal windows below to the current windows
set encoding=utf-8              " Set default encoding to UTF-8
set fileformats=unix,dos,mac    " Prefer Unix over Windows over OS 9 formats
set autowrite                   " Automatically save before :next, :make etc.
set autoread                    " Automatically reread changed files without asking me anything
" Ask for confirmation to save file when switching between files
set confirm
"set noswapfile                  " Don't use swapfile
"set nobackup	                 " Don't create annoying backup files
"set nowritebackup
set hidden                      " Opening a new file hides current buffer instead of closing
"au FocusLost * :wa              " Set vim to save the file on focus out (only works on GUI VIM).

set ttyfast
" set ttyscroll=3               " noop on linux ?
set lazyredraw          	      " Wait to redraw "
" speed up syntax highlighting
set nocursorcolumn
set nocursorline

syntax sync minlines=256
set synmaxcol=300
set re=1                        " Use the old regex engine (faster/better)


" Better command-line completion
set wildmenu
"set wildmode=list:full
" Always display the status line, even if only one window is displayed
set laststatus=2


" Use case insensitive search, except when using capital letters
set ignorecase
set smartcase
set incsearch                   " Shows the match while typing
set hlsearch                    " Highlight found searches

" Allow backspacing over autoindent, line breaks and start of insert action
set backspace=indent,eol,start

" Stop certain movements from always going to the first character of a line.
" While this behaviour deviates from that of Vi, it does what most users
" coming from other editors would expect.
set nostartofline

" Display the cursor position on the last line of the screen or in the status
" line of a window
set ruler
" Display line numbers on the left
set number
" Set the command window height to 2 lines, to avoid many cases of having to
" "press <Enter> to continue"
set cmdheight=2


" In many terminal emulators the mouse works just fine, thus enable it.
if has('mouse')
  " Enable use of the mouse for all modes
  set mouse=a
endif

" Quickly time out on keycodes, but never time out on mappings
set notimeout ttimeout ttimeoutlen=100

set nrformats-=octal
set shiftround

"------------------------------------------------------------
" Indentation options

" When opening a new line and no filetype-specific indenting is enabled, keep
" the same indent as the line you're currently on. Useful for READMEs, etc.
set autoindent
set showmatch
set smarttab

" Indentation settings for using 2 spaces instead of tabs.
set shiftwidth=2
set softtabstop=2
set tabstop=4
set expandtab

" Better Completion
set complete-=i                 " Same effect as  complete=.,w,b,u,t
set completeopt=longest,menuone


" open help vertically
command! -nargs=* -complete=help Help vertical belowright help <args>
autocmd FileType help wincmd L

" Convenient command to see the difference between the current buffer and the
" file it was loaded from, thus the changes you made.
" Only define it when not defined already.
if !exists(":DiffOrig")
	command DiffOrig vert new | set bt=nofile | r # | 0d_ | diffthis
				\ | wincmd p | diffthis
endif

" Only do this part when compiled with support for autocommands.
if has("autocmd")

  " Enable file type detection.
  " Use the default filetype settings, so that mail gets 'tw' set to 72,
  " 'cindent' is on in C files, etc.
  " Also load indent files, to automatically do language-dependent indenting.
  filetype plugin indent on

  " Put these in an autocmd group, so that we can delete them easily.
  augroup vimrcEx
    au!

    " For all text files set 'textwidth' to 120 characters.
    autocmd FileType text setlocal textwidth=120

    " When editing a file, always jump to the last known cursor position.
    " Don't do it when the position is invalid or when inside an event handler
    " (happens when dropping a file on gvim).
    " Also don't do it when the mark is in the first line, that is the default
    " position when opening a file.
    autocmd BufReadPost *
          \ if line("'\"") > 1 && line("'\"") <= line("$") |
          \	exe "normal! g`\"" |
          \ endif

  augroup END
else
endif " has("autocmd")



" netrw settings.
" Don't create ~/.vim/.netrwhist history file.
let g:netrw_dirhistmax = 0

" This comes first, because we have mappings that depend on leader
" With a map leader it's possible to do extra key combinations
" i.e: <leader>w saves the current file
let mapleader = ","
let g:mapleader = ","

" This trigger takes advantage of the fact that the quickfix window can be
" easily distinguished by its file-type, qf. The wincmd J command is
" equivalent to the Ctrl+W, Shift+J shortcut telling Vim to move a window to
" the very bottom (see :help :wincmd and :help ^WJ).
autocmd FileType qf wincmd J

" Some useful quickfix shortcuts
":cc      see the current error
":cn      next error
":cp      previous error
":clist   list all errors
map <leader>n :cn<CR>
map <leader>m :cp<CR>
" Mapping to navigate to current / first result
map <leader>cc :cc<CR>

" Close quickfix easily
nnoremap <leader>c :cclose<CR>

" And location counterparts
map <leader>. :lnext<CR>
map <leader>, :lprevious<CR>
" Mapping to navigate to current / first result
map <leader>ll :ll<CR>

nnoremap <leader>l :lclose<CR>


nnoremap <silent> <leader>q :Sayonara<CR>

" Fast saving
nmap <leader>w :w!<cr>

" Center the screen
nnoremap <space> zz

" Move up and down on splitted lines (on small width screens)
map <Up> gk
map <Down> gj
map k gk
map j gj

" Better split switching
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" Search mappings: These will make it so that going to the next one in a
" search will center on the line it's found in.
nnoremap n nzzzv
nnoremap N Nzzzv

" Set CTRL+L to redraw the screen and turn off search highlights
nnoremap <silent> <C-l> :nohlsearch<CR><C-l>
" Remove search highlight
nnoremap <leader><space> :nohlsearch<CR>

" Allow saving of files as sudo when I forgot to start vim using sudo.
" typing  :w!!  will sudo-save the file
cmap w!! w !sudo tee > /dev/null %

" Set CTRL+C to copy to the system clipboard
vnoremap <C-c> "+y

" Replace the current buffer with the given new file. That means a new file
" will be open in a buffer while the old one will be deleted
com! -nargs=1 -complete=file Breplace edit <args>| bdelete #

function! DeleteInactiveBufs()
  "From tabpagebuflist() help, get a list of all buffers in all tabs
  let tablist = []
  for i in range(tabpagenr('$'))
    call extend(tablist, tabpagebuflist(i + 1))
  endfor

  "Below originally inspired by Hara Krishna Dara and Keith Roberts
  "http://tech.groups.yahoo.com/group/vim/message/56425
  let nWipeouts = 0
  for i in range(1, bufnr('$'))
    if bufexists(i) && !getbufvar(i,"&mod") && index(tablist, i) == -1
      "bufno exists AND isn't modified AND isn't in the list of buffers open in windows and tabs
      silent exec 'bwipeout' i
      let nWipeouts = nWipeouts + 1
    endif
  endfor
  echomsg nWipeouts . ' buffer(s) wiped out'
endfunction

command! Ball :call DeleteInactiveBufs()


" Make Vim to handle long lines nicely.
set wrap
set textwidth=120
set formatoptions=qrn1
"set colorcolumn=120
"set relativenumber
"set norelativenumber
" set 120 character line limit
if exists('+colorcolumn')
  set colorcolumn=120
else
  au BufWinEnter * let w:m2=matchadd('ErrorMsg', '\%>120v.\+', -1)
endif

" ----------------------------------------- "
" File Type settings 			    		"
" ----------------------------------------- "

au BufNewFile,BufRead *.vim setlocal noet ts=4 sw=4 sts=4
au BufNewFile,BufRead *.txt setlocal noet ts=4 sw=4
au BufNewFile,BufRead *.md setlocal spell noet ts=4 sw=4
au BufNewFile,BufRead *.yml,*.yaml setlocal expandtab ts=2 sw=2
au BufNewFile,BufRead *.cpp setlocal expandtab ts=2 sw=2
au BufNewFile,BufRead *.hpp setlocal expandtab ts=2 sw=2
au BufNewFile,BufRead *.json setlocal expandtab ts=2 sw=2

augroup filetypedetect
  au BufNewFile,BufRead .tmux.conf*,tmux.conf* setf tmux
  au BufNewFile,BufRead .nginx.conf*,nginx.conf* setf nginx
augroup END

au FileType nginx setlocal noet ts=4 sw=4 sts=4

" Go settings
au BufNewFile,BufRead *.go setlocal noet ts=4 sw=4 sts=4

" Markdown Settings
autocmd BufNewFile,BufReadPost *.md setl ts=4 sw=4 sts=4 expandtab

" Dockerfile settings
autocmd FileType dockerfile set noexpandtab

" shell/config/systemd settings (don't expand tab in shell scripts due to here-doc)
autocmd FileType fstab,systemd set noexpandtab
autocmd FileType gitconfig,sh set noexpandtab

" python indent
autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 shiftwidth=4 textwidth=80 smarttab expandtab

" spell check for git commits
autocmd FileType gitcommit setlocal spell


" Ignore patterns for globbing
set wildignore+=.hg,.git,.svn                    " Version control
set wildignore+=*.aux,*.out,*.toc                " LaTeX intermediate files
set wildignore+=*.jpg,*.bmp,*.gif,*.png,*.jpeg   " binary images
set wildignore+=*.o,*.obj,*.exe,*.dll,*.manifest " compiled object files
set wildignore+=*.spl                            " compiled spelling word lists
set wildignore+=*.sw?                            " Vim swap files
set wildignore+=*.DS_Store                       " OSX bullshit
set wildignore+=*.luac                           " Lua byte code
set wildignore+=migrations                       " Django migrations
set wildignore+=go/pkg                           " Go static files
set wildignore+=go/bin                           " Go bin files
set wildignore+=go/bin-vagrant                   " Go bin-vagrant files
set wildignore+=*.pyc                            " Python byte code
set wildignore+=*.orig                           " Merge resolution files


" ----------------------------------------- "
" Plugin configs 			    "
" ----------------------------------------- "

" ================= Ack / Ag =================
" Use ack.vim plugin as wrapper for AG, to search within project files
if executable('ag')
  let g:ackprg = 'ag --vimgrep --smart-case'
  cnoreabbrev ag Ack
  cnoreabbrev aG Ack
  cnoreabbrev Ag Ack
  cnoreabbrev AG Ack
endif


" =================== vim-airline ========================

let g:airline_theme='solarized'

" Could enable powerline fonts when installed, but only works
" when installing 'patched' fonts and URXVT uses this same
" patched font...
"let g:airline_powerline_fonts=1

" Override some default symbols which otherwise have difficulty showing
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif
let g:airline_symbols.branch='⎇'
"let g:airline_symbols.branch='⮀'
let g:airline_symbols.maxlinenr=''


" ========= vim-better-whitespace ==================

" auto strip whitespace except for file with extention blacklisted
let blacklist = ['diff', 'gitcommit', 'unite', 'qf', 'help']
autocmd BufWritePre * if index(blacklist, &ft) < 0 | StripWhitespace


" ==================== CtrlP ====================
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_max_height = 10		" maxiumum height of match window
let g:ctrlp_switch_buffer = 'et'	" jump to a file if it's open already
let g:ctrlp_mruf_max=450 		" number of recently opened files
let g:ctrlp_max_files=0  		" do not limit the number of searchable files
let g:ctrlp_use_caching = 1
let g:ctrlp_clear_cache_on_exit = 1
let g:ctrlp_cache_dir = $HOME.'/.cache/ctrlp'

" ignore files in .gitignore
let g:ctrlp_user_command = ['.git', 'cd %s && git ls-files -co --exclude-standard']


" ==================== Completion =========================
" use deoplete for Neovim.
if has('nvim')
  let g:deoplete#enable_at_startup = 1
  let g:deoplete#ignore_sources = {}
  let g:deoplete#ignore_sources._ = ['buffer', 'member', 'tag', 'file', 'neosnippet']

  " Use partial fuzzy matches like YouCompleteMe
  call deoplete#custom#source('_', 'matchers', ['matcher_fuzzy'])
  call deoplete#custom#source('_', 'converters', ['converter_remove_paren'])
  call deoplete#custom#source('_', 'disabled_syntaxes', ['Comment', 'String'])
endif


" ==================== delimitMate ====================
let g:delimitMate_expand_cr = 1
let g:delimitMate_expand_space = 1
let g:delimitMate_smart_quotes = 1
let g:delimitMate_expand_inside_quotes = 0
let g:delimitMate_smart_matchpairs = '^\%(\w\|\$\)'


" =============== Erlang Skeletons =================
" Erlang skeleton variables
let g:erl_author="Miel Donkers"
let g:erl_company="Instana"


" ==================== Fugitive ====================
nnoremap <leader>ga :Git add %:p<CR><CR>
nnoremap <leader>gs :Gstatus<CR>


" ==================== vim-multiple-cursors ====================
let g:multi_cursor_use_default_mapping=0
let g:multi_cursor_next_key='<C-i>'
let g:multi_cursor_prev_key='<C-y>'
let g:multi_cursor_skip_key='<C-b>'
let g:multi_cursor_quit_key='<Esc>'

" Called once right before you start selecting multiple cursors
function! Multiple_cursors_before()
  if exists(':NeoCompleteLock')==2
    exe 'NeoCompleteLock'
  endif
endfunction

" Called once only when the multiple selection is canceled (default <Esc>)
function! Multiple_cursors_after()
  if exists(':NeoCompleteUnlock')==2
    exe 'NeoCompleteUnlock'
  endif
endfunction


"==================== NeoMake =====================

call neomake#configure#automake('nw', 1000)
" Open the location-list when issues are found
let g:neomake_open_list = 2
" Enabled makers for different languages
let g:neomake_elixir_enabled_makers = ['mix', 'credo']


"==================== NerdTree ====================
" For toggling
nmap <C-n> :NERDTreeToggle<CR>
"noremap <Leader>n :NERDTreeToggle<cr> " Clashes with quickfix shortcuts
noremap <Leader>f :NERDTreeFind<cr>

let NERDTreeShowHidden=1
" Don't replace Netrw as default file explorer, e.g. during Vim startup
let NERDTreeHijackNetrw=0

let NERDTreeIgnore=['\.vim$', '\~$', '\.git$', '.DS_Store', '.stfolder']

" Close nerdtree and vim on close file
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTreeType") && b:NERDTreeType == "primary") | q | endif
