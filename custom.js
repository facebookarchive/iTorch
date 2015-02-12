$([IPython.events]).on('notebook_loaded.Notebook', function(){
    // add here logic that should be run once per **notebook load**
    // (!= page load), like restarting a checkpoint
    var md = IPython.notebook.metadata
    if(md.language){
        console.log('language already defined and is :', md.language);
    } else {
        md.language = 'lua' ;
	console.log('add metadata hint that language is lua');
    }
});

// logic per page-refresh
$([IPython.events]).on("app_initialized.NotebookApp", function () {
    $('head').append('<link rel="stylesheet" type="text/css" href="custom.css">');
	
    
    IPython.CodeCell.options_default['cm_config']['mode'] = 'lua';

    CodeMirror.requireMode('lua', function(){
	IPython.OutputArea.prototype._should_scroll = function(){return false}
        cells = IPython.notebook.get_cells();
        for(var i in cells){
            c = cells[i];
            if (c.cell_type === 'code'){
                c.auto_highlight()
            }
        }
    });
    

});
