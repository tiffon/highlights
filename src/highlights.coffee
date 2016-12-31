path = require 'path'
_ = require 'underscore-plus'
fs = require 'fs-plus'
CSON = require 'season'
{GrammarRegistry} = require 'first-mate'
Selector = require 'first-mate-select-grammar'
selector = Selector()


module.exports =
class Highlights
  # Public: Create a new highlighter.
  #
  # options - An Object with the following keys:
  #   :includePath - An optional String path to a file or folder of grammars to
  #                  register.
  #   :registry    - An optional GrammarRegistry instance.
  constructor: ({@includePath, @registry}={}) ->
    @registry ?= new GrammarRegistry(maxTokensPerLine: Infinity)

  loadGrammarsSync: ->
    return if @registry.grammars.length > 1

    if typeof @includePath is 'string'
      if fs.isFileSync(@includePath)
        @registry.loadGrammarSync(@includePath)
      else if fs.isDirectorySync(@includePath)
        for filePath in fs.listSync(@includePath, ['cson', 'json'])
          @registry.loadGrammarSync(filePath)

    grammarsPath = path.join(__dirname, '..', 'gen', 'grammars.json')
    for grammarPath, grammar of JSON.parse(fs.readFileSync(grammarsPath))
      continue if @registry.grammarForScopeName(grammar.scopeName)?
      grammar = @registry.createGrammar(grammarPath, grammar)
      @registry.addGrammar(grammar)

  # Public: Require all the grammars from the grammars folder at the root of an
  #   npm module.
  #
  # modulePath - the String path to the module to require grammars from. If the
  #              given path is a file then the grammars folder from the parent
  #              directory will be used.
  requireGrammarsSync: ({modulePath}={}) ->
    @loadGrammarsSync()

    if fs.isFileSync(modulePath)
      packageDir = path.dirname(modulePath)
    else
      packageDir = modulePath

    grammarsDir = path.resolve(packageDir, 'grammars')

    return unless fs.isDirectorySync(grammarsDir)

    for file in fs.readdirSync(grammarsDir)
      if grammarPath = CSON.resolve(path.join(grammarsDir, file))
        @registry.loadGrammarSync(grammarPath)

  # Public: Syntax highlight the given file synchronously.
  #
  # options - An Object with the following keys:
  #   :fileContents - The optional String contents of the file. The file will
  #                   be read from disk if this is unspecified
  #   :filePath     - The String path to the file.
  #   :scopeName    - An optional String scope name of a grammar. The best match
  #                   grammar will be used if this is unspecified.
  #
  # Returns a String of HTML. The HTML will contains one <pre> with one <div>
  # per line and each line will contain one or more <span> elements for the
  # tokens in the line.
  highlightSync: ({filePath,
                   fileContents,
                   scopeName,
                   startingLineNum,
                   lineEm,
                   idHandle}={}) ->
    @loadGrammarsSync()

    fileContents ?= fs.readFileSync(filePath, 'utf8') if filePath
    grammar = @registry.grammarForScopeName(scopeName)
    # grammar ?= @registry.selectGrammar(filePath, fileContents)
    grammar ?= selector.selectGrammar(@registry, filePath, fileContents)
    lineTokens = grammar.tokenizeLines(fileContents)
    if startingLineNum
      useLineNums = true
      lineNum = startingLineNum
      useNumAnchor = !!idHandle
      if lineEm
        lineEm = lineEm.split(',')
      else
        lineEm = []
    else
      useLineNums = false
      lineNum = NaN
      lineEm = []

    console.log('useline numes:', useLineNums, lineNum)
    # Remove trailing newline
    if lineTokens.length > 0
      lastLineTokens = lineTokens[lineTokens.length - 1]
      if lastLineTokens.length is 1 and lastLineTokens[0].value is ''
        lineTokens.pop()
    console.log('lineEm:', lineEm)
    html = '<pre class="editor editor-colors'
    if useLineNums
      html += ' with-line-numbers">'
      html += '<table><tbody>'
      trCssClasses = 'highlight-numbered-line'
      if useNumAnchor
        trCssClasses += ' code-is-anchored'
    else
      html += ' without-line-numbers">'

    for tokens in lineTokens
      scopeStack = []
      if useLineNums
        if lineEm.indexOf('' + lineNum) > -1
          lineEmClass = "line-em"
        else
          lineEmClass = ""
        html += """
          <tr class="#{ trCssClasses } #{ lineEmClass }">
            <td class="highlight-line-num" data-line-num="#{ lineNum }">"""
        if useNumAnchor
          html += """
            <a  class="code-anchor"
                id="code-#{ idHandle }-#{ lineNum }"
                href="#code-#{ idHandle }-#{ lineNum }">
            </a>"""
        html += """
          </td>
          <td class="highlight-line">"""
      else
        html += '<div class="highlight-line">'
      for {scopes, value} in tokens
        value = ' ' unless value
        html = @updateScopeStack(scopeStack, scopes, html)
        html += "<span>#{@escapeString(value)}</span>"
      html = @popScope(scopeStack, html) while scopeStack.length > 0
      if useLineNums
        html += '</td></tr>'
        lineNum++
      else
        html += '</div>'
    if useLineNums
      html += '</tbody></table>'
    html += '</pre>'
    # consoel.log('result:', html);
    html

  escapeString: (string) ->
    string.replace /[&"'<> ]/g, (match) ->
      switch match
        when '&' then '&amp;'
        when '"' then '&quot;'
        when "'" then '&#39;'
        when '<' then '&lt;'
        when '>' then '&gt;'
        when ' ' then '&nbsp;'
        else match

  updateScopeStack: (scopeStack, desiredScopes, html) ->
    excessScopes = scopeStack.length - desiredScopes.length
    if excessScopes > 0
      html = @popScope(scopeStack, html) while excessScopes--

    # pop until common prefix
    for i in [scopeStack.length..0]
      break if _.isEqual(scopeStack[0...i], desiredScopes[0...i])
      html = @popScope(scopeStack, html)

    # push on top of common prefix until scopeStack is desiredScopes
    for j in [i...desiredScopes.length]
      html = @pushScope(scopeStack, desiredScopes[j], html)

    html

  pushScope: (scopeStack, scope, html) ->
    scopeStack.push(scope)
    html += "<span class=\"#{scope.replace(/\.+/g, ' ')}\">"

  popScope: (scopeStack, html) ->
    scopeStack.pop()
    html += '</span>'
