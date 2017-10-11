debug = require('./debug.ts')
zoteroCconfig = require('./zotero-config.ts')

Prefs = require('./prefs.ts')
Formatter = require('./keymanager/formatter.coffee')
KeyManager = require('./keymanager.coffee')
AutoExport = require('./auto-export.ts')
Translators = require('./translators.ts')

AutoExportName = (ae, full) ->
  switch ae.type
    when 'library'
      name = Zotero.Libraries.getName(ae.id)
    when 'collection'
      if full
        name = AutoExportName.collectionPath(ae.id)
      else
        name = Zotero.Collections.get(ae.id).name
  return name || ae.path
AutoExportName.collectionPath = (id) ->
  return '' unless id
  coll = Zotero.Collections.get(id)
  return '' unless coll

  return AutoExportName.collectionPath(coll.parent) + '/' + coll.name if coll.parent
  return coll.name

class AutoExportPrefPane
  remove: ->
    return unless exportlist = document.getElementById('better-bibtex-export-list')
    selected = exportlist.currentIndex
    return if selected < 0

    id = parseInt(exportlist.contentView.getItemAtIndex(selected).getAttribute('autoexport'))
    debug('AutoExport: removing', { id })
    AutoExport.db.remove(id)
    @refresh()
    return

  mark: ->
    return unless exportlist = document.getElementById('better-bibtex-export-list')
    selected = exportlist.currentIndex
    return if selected < 0

    id = parseInt(parseInt(exportlist.contentView.getItemAtIndex(selected).getAttribute('autoexport')))
    AutoExport.run(id)
    @refresh()
    return

  refresh: ->
    if !AutoExport.db
      debug('AutoExportPrefPane.refresh: DB not loaded')
      return

    return unless exportlist = document.getElementById('better-bibtex-auto-exports')
    while exportlist.hasChildNodes()
      exportlist.removeChild(exportlist.firstChild)

    for ae in AutoExport.db.chain().simplesort('path').data()
      treeitem = exportlist.appendChild(document.createElement('treeitem'))
      treeitem.setAttribute('autoexport', "#{ae.$loki}")

      treerow = treeitem.appendChild(document.createElement('treerow'))
      cells = [
        { label: "#{ae.type}: #{AutoExportName(ae)}" }
        { label: ae.status + (if ae.updated then " (#{ae.updated})" else ''), tooltip: ae.error }
        { label: ae.path.replace(/.*[\\\/]/, ''), tooltip: ae.path }
        { label: Translators.byId[ae.translatorID]?.label || '??' }
        { label: '' + ae.useJournalAbbreviation }
        { label: '' + ae.exportNotes }
      ]
      for cell in cells
        debug('Preferences.AutoExport.refresh:', cell)
        treecell = treerow.appendChild(document.createElement('treecell'))
        treecell.setAttribute('editable', 'false')
        treecell.setAttribute('label', cell.label)
        treecell.setAttribute('tooltiptext', cell.tooltip) if cell.tooltip

    return

class PrefPane
  load: ->
    debug('PrefPane.new: loading...')
    return if typeof Zotero_Preferences == 'undefined'

    @AutoExport = new AutoExportPrefPane()

    # document.getElementById('better-bibtex-prefs-tab-journal-abbrev').setAttribute('hidden', !zoteroCconfig.isJurisM)
    document.getElementById('better-bibtex-abbrev-style').setAttribute('hidden', !zoteroCconfig.isJurisM)

    if !Zotero_Preferences.openHelpLink.BetterBibTeX
      Zotero_Preferences.openHelpLink.BetterBibTeX = Zotero_Preferences.openHelpLink
      Zotero_Preferences.openHelpLink = ->
        helpTopic = document.getElementsByTagName('prefwindow')[0].currentPane.helpTopic
        if helpTopic == 'BetterBibTeX'
          id = document.getElementById('better-bibtex-prefs-tabbox').selectedPanel.id
          return unless id
          url = 'https://github.com/retorquere/zotero-better-bibtex/wiki/Configuration#' + id.replace('better-bibtex-prefs-', '')
          ### Just a temporary fix until https://github.com/zotero/zotero/issues/949 is fixed ###
          if Zotero.Prefs.get(['browser', 'preferences', 'instantApply'].join('.'), true)
            Zotero.getActiveZoteroPane().loadURI(url, { shiftKey: true, metaKey: true })
          else
            @openURL(url)
        else
          Zotero_Preferences.openHelpLink.BetterBibTeX.apply(@, arguments)
        return

    @getCitekeyFormat()
    @update()

    debug('PrefPane.new loaded @', document.location.hash)

    if document.location.hash == '#better-bibtex'
      ### TODO: runs into the 'TypeError: aId is undefined' problem for some reason. ###
      setTimeout((-> document.getElementById('zotero-prefs').showPane(document.getElementById('zotero-prefpane-better-bibtex'))), 500)
    debug('PrefPane.new: ready')
    return

  getCitekeyFormat: ->
    debug('PrefPane.getCitekeyFormat...')
    keyformat = document.getElementById('id-better-bibtex-preferences-citekeyFormat')
    keyformat.value = Prefs.get('citekeyFormat')
    debug('PrefPane.getCitekeyFormat got', keyformat.value)
    return

  checkCitekeyFormat: ->
    keyformat = document.getElementById('id-better-bibtex-preferences-citekeyFormat')

    msg = ''
    try
      Formatter.parsePattern(keyformat.value)
      msg = ''
    catch err
      msg = '' + err

    keyformat.setAttribute('style', (if msg then '-moz-appearance: none !important; background-color: DarkOrange' else ''))
    keyformat.setAttribute('tooltiptext', msg)
    return

  saveCitekeyFormat: ->
    keyformat = document.getElementById('id-better-bibtex-preferences-citekeyFormat')
    try
      Formatter.parsePattern(keyformat.value)
      Prefs.set('citekeyFormat', keyformat.value)
    catch
      @getCitekeyFormat()
    return

  checkPostscript: ->
    postscript = document.getElementById('zotero-better-bibtex-postscript')

    error = false
    try
      new Function(postscript.value)
    catch err
      debug('PrefPane.checkPostscript: error compiling postscript:', err)
      error = '' + err

    postscript.setAttribute('style', (if error then '-moz-appearance: none !important; background-color: DarkOrange' else ''))
    postscript.setAttribute('tooltiptext', error || '')
    return

  styleChanged: (index) ->
    return unless zoteroCconfig.isJurisM

    stylebox = document.getElementById('better-bibtex-abbrev-style')
    selectedItem = if typeof index != 'undefined' then stylebox.getItemAtIndex(index) else stylebox.selectedItem
    styleID = selectedItem.getAttribute('value')
    Prefs.set('autoAbbrevStyle', styleID)
    return

  # TODO: allow clean-scan?
  rescanCitekeys: Zotero.Promise.coroutine(->
    debug('starting manual key rescan')
    yield KeyManager.rescan()
    debug('manual key rescan done')
    return
  )

  display: (id, text) ->
    elt = document.getElementById(id)
    elt.value = text
    elt.setAttribute('tooltiptext', text) if text != ''
    return

  update: ->
    @checkCitekeyFormat()

    patternError = null
    try
      Formatter.parsePattern(keyformat.value)
    catch err
      patternError = err

    if zoteroCconfig.isJurisM
      Zotero.Styles.init().then(=>
        styles = (style for style in Zotero.Styles.getVisible() when style.usesAbbreviation)
        debug('prefPane.update: found styles', styles)

        stylebox = document.getElementById('better-bibtex-abbrev-style')
        refill = stylebox.children.length == 0
        selectedStyle = Prefs.get('autoAbbrevStyle')
        selectedIndex = -1
        for style, i in styles
          if refill
            itemNode = document.createElement('listitem')
            itemNode.setAttribute('value', style.styleID)
            itemNode.setAttribute('label', style.title)
            stylebox.appendChild(itemNode)
          if style.styleID == selectedStyle then selectedIndex = i
        selectedIndex = 0 if selectedIndex == -1
        @styleChanged(selectedIndex)

        setTimeout((->
          stylebox.ensureIndexIsVisible(selectedIndex)
          stylebox.selectedIndex = selectedIndex
          return), 0)

        return
      )

    @AutoExport.refresh()

    return

  # TODO: caching
#  cacheReset: ->
#    @cache.reset('user request')
#    @serialized.reset('user request')

module.exports = new PrefPane()

window.addEventListener('load', (-> module.exports.load()), false)

# otherwise this entry point won't be reloaded: https://github.com/webpack/webpack/issues/156
delete require.cache[module.id]