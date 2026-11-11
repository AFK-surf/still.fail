// What HTML's elements are before any stylesheet says otherwise: the parts of a browser's user-agent sheet a widget
// is drawn with (HTML's rendering section: which elements are blocks, lists, tables, what is bold or italic or code,
// headings' sizes, a paragraph's margins). What draws a widget puts its own look over it (the app's defaults sheet).

///|
pub let ua_css : String =
  #|address, article, aside, blockquote, body, center, dd, details, dialog, dir, div, dl, dt, fieldset, figcaption,
  #|figure, footer, form, h1, h2, h3, h4, h5, h6, header, hgroup, hr, html, legend, listing, main, menu, nav, ol, p,
  #|plaintext, pre, search, section, summary, ul, xmp { display: block; }
  #|li { display: list-item; }
  #|table { display: table; }
  #|caption { display: table-caption; }
  #|colgroup { display: table-column-group; }
  #|col { display: table-column; }
  #|thead { display: table-header-group; }
  #|tbody { display: table-row-group; }
  #|tfoot { display: table-footer-group; }
  #|tr { display: table-row; }
  #|td, th { display: table-cell; }
  #|button, input, select, textarea, meter, progress, img, svg { display: inline-block; }
  #|[hidden], area, base, datalist, head, link, meta, noscript, rp, script, style, template, title { display: none; }
  #|p, blockquote, figure, dl, ol, ul, pre { margin-top: 1em; margin-bottom: 1em; }
  #|dd { margin-left: 40px; }
  #|ol, ul, menu { padding-left: 40px; }
  #|ol { list-style-type: decimal; }
  #|ul ul, ol ul { list-style-type: circle; margin-top: 0; margin-bottom: 0; }
  #|ul ul ul, ol ul ul { list-style-type: square; }
  #|ol ol, ul ol { margin-top: 0; margin-bottom: 0; }
  #|h1 { font-size: 2em; margin-top: .67em; margin-bottom: .67em; font-weight: bold; }
  #|h2 { font-size: 1.5em; margin-top: .83em; margin-bottom: .83em; font-weight: bold; }
  #|h3 { font-size: 1.17em; margin-top: 1em; margin-bottom: 1em; font-weight: bold; }
  #|h4 { margin-top: 1.33em; margin-bottom: 1.33em; font-weight: bold; }
  #|h5 { font-size: .83em; margin-top: 1.67em; margin-bottom: 1.67em; font-weight: bold; }
  #|h6 { font-size: .67em; margin-top: 2.33em; margin-bottom: 2.33em; font-weight: bold; }
  #|th, b, strong { font-weight: bold; }
  #|i, cite, em, var, dfn { font-style: italic; }
  #|code, kbd, samp, tt, pre { font-family: monospace; }
  #|pre { white-space: pre; }
  #|s, strike, del { text-decoration: line-through; }
  #|u, ins { text-decoration: underline; }
  #|a { text-decoration: underline; color: #0000ee; }
  #|small { font-size: smaller; }
  #|big { font-size: larger; }
  #|sub, sup { font-size: smaller; }
  #|mark { background-color: yellow; color: black; }
  #|hr { border-top: 1px solid gray; margin: .5em 0; }
  #|th { text-align: center; }
  #|td, th { padding: 1px; }
  #|center { text-align: center; }
  #|blockquote, figure { margin-left: 40px; margin-right: 40px; }
  #|button { padding: 1px 6px; text-align: center; }
  #|summary { display: block; }
  #|details > :not(summary) { display: none; }
  #|details[open] > :not(summary) { display: block; }
