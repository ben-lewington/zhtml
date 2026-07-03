local group = vim.api.nvim_create_augroup("tml_syntax", { clear = true })

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = group,
  pattern = "*.tml",
  callback = function()
    vim.bo.filetype = "tml"
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "tml",
  callback = function()
    vim.b.current_syntax = nil

    vim.cmd([[
      syntax clear

      " -----------------
      " top-level strings
      " -----------------
      syntax region tmlTopStringD start=/"/ end=/"/ keepend
      syntax region tmlTopStringS start=/'/ end=/'/ keepend

      " -----------------
      " comments / meta
      " -----------------
      syntax region tmlComment start=/#/ end=/#/ keepend
      syntax region tmlMeta start=/!/ end=/!/ keepend contains=tmlTopStringD,tmlTopStringS

      " bare close node lines/tokens
      syntax match tmlCloseNode /^\s*>\s*$/
      syntax match tmlCloseNode /\s\zs>\ze\(\s\|$\)/

      " -----------------
      " tag
      " -----------------
      syntax region tmlTag
            \ start=/</
            \ end=/>/
            \ keepend
            \ transparent
            \ contains=tmlTagDelimiter,tmlPipe,tmlTagName,tmlClassAttr,tmlIdAttr,tmlAttrAssignD,tmlAttrAssignS,tmlAttrKey,tmlEquals,tmlBareAttr,tmlTagBody

      syntax match tmlTagDelimiter /</ contained
      syntax match tmlTagDelimiter />/ contained
      syntax match tmlPipe /|/ contained

      " tag name = first token after <
      syntax match tmlTagName /<\s*\zs[A-Za-z_][A-Za-z0-9_-]*/ contained

      " attrs in the head
      syntax match tmlClassAttr /\s\zs\.[A-Za-z_][A-Za-z0-9_-]*/ contained
      syntax match tmlIdAttr    /\s\zs#[A-Za-z_][A-Za-z0-9_-]*/ contained

      " key=value attrs after whitespace
      syntax match tmlAttrKey /\s\zs[A-Za-z_][A-Za-z0-9_-]*\ze=/ contained
      syntax match tmlEquals /=/ contained

      syntax region tmlAttrAssignD
            \ start=/\s[A-Za-z_][A-Za-z0-9_-]*="/
            \ end=/"/
            \ contained
            \ contains=tmlAttrKey,tmlEquals,tmlAttrStringD

      syntax region tmlAttrAssignS
            \ start=/\s[A-Za-z_][A-Za-z0-9_-]*='/
            \ end=/'/
            \ contained
            \ contains=tmlAttrKey,tmlEquals,tmlAttrStringS

      syntax region tmlAttrStringD
            \ start=/"/
            \ end=/"/
            \ contained

      syntax region tmlAttrStringS
            \ start=/'/
            \ end=/'/
            \ contained

      " bare attrs after whitespace
      syntax match tmlBareAttr /\s\zs[A-Za-z_][A-Za-z0-9_-]*\ze\(\s\||\|>\)/ contained

      " -----------------
      " tag body after |
      " -----------------
      syntax region tmlTagBody
            \ start=/|/
            \ end=/>/
            \ keepend
            \ contained
            \ transparent
            \ contains=tmlPipe,tmlBodyText,tmlBodyStringD,tmlBodyStringS

      syntax region tmlBodyStringD
            \ start=/"/
            \ end=/"/
            \ contained

      syntax region tmlBodyStringS
            \ start=/'/
            \ end=/'/
            \ contained

      syntax match tmlBodyText /[^\t\r\n <>|"'#!=][^\t\r\n <>|]*/ contained

      " -----------------
      " top-level text
      " -----------------
      syntax match tmlTopText /[^[:space:]<#!'"][^[:space:]<>'"]*/

      " -----------------
      " highlight links
      " -----------------
      highlight! link tmlTagDelimiter Delimiter
      highlight! link tmlCloseNode Delimiter
      highlight! link tmlPipe Special

      highlight! link tmlTagName Function
      highlight! link tmlClassAttr Type
      highlight! link tmlIdAttr Identifier
      highlight! link tmlAttrKey Keyword
      highlight! link tmlEquals Operator
      highlight! link tmlBareAttr Constant

      highlight! link tmlAttrStringD String
      highlight! link tmlAttrStringS String
      highlight! link tmlBodyStringD String
      highlight! link tmlBodyStringS String
      highlight! link tmlTopStringD String
      highlight! link tmlTopStringS String

      highlight! link tmlBodyText Normal
      highlight! link tmlTopText Normal

      highlight! link tmlComment Comment
      highlight! link tmlMeta PreProc

      let b:current_syntax = "tml"
    ]])

    if not string.find(vim.bo.matchpairs, "<:>", 1, true) then
      vim.bo.matchpairs = vim.bo.matchpairs .. ",<:>"
    end
  end,
})
