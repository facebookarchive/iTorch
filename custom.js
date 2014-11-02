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
    $.ajax({
        url: "http://cdn.pydata.org/bokeh-0.6.1.min.js",
        dataType: "script",
        async: false,
        success: function () {},
        error: function () {
            throw new Error("Could not load bokeh.js");
        }
    });
    $('head').append('<link rel="stylesheet" type="text/css" href="http://cdn.pydata.org/bokeh-0.6.1.min.css">');
	
    
    IPython.CodeCell.options_default['cm_config']['mode'] = 'lua';

    CodeMirror.requireMode('lua', function(){
        cells = IPython.notebook.get_cells();
        for(var i in cells){
            c = cells[i];
            if (c.cell_type === 'code'){
                c.auto_highlight()
            }
        }
    });
    

});
