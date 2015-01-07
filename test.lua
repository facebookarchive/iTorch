-- images
itorch.image(image.lena())
itorch.image({image.lena(), image.lena(), image.lena()})

-- audio
itorch.audio('volkswagen.mp3')

-- video
itorch.video('chase.ogv')

-- html
itorch.html('<p><b>Hi there!</b> how are you</p>')
window_id = itorch.html('<p>This text will be replaced in 2 seconds</p>')
os.execute('sleep 2')
itorch.html('<p>magic!</p>', window_id)

x1 = torch.randn(40):mul(100)
y1 = torch.randn(40):mul(100)
x2 = torch.randn(40):mul(100)
y2 = torch.randn(40):mul(100)
x3 = torch.randn(40):mul(200)
y3 = torch.randn(40):mul(200)

-- scatter plots
local Plot = require 'itorch.Plot'
plot = Plot():add(x1, y1, 'red', 'hi'):add(x2, y2, 'blue', 'bye'):draw()
plot:add(x3,y3,'green', 'yolo'):redraw()
plot:title(' My plot!'):redraw()
plot:xaxis('length'):yaxis('width'):redraw()
plot:legend(true)
plot:redraw()
-- print(plot:toHTML())
plot:save('out.html')



