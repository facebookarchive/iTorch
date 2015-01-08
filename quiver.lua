xx = torch.linspace(-3,3,10)
yy = torch.linspace(-3,3,10)
local function meshgrid(x,y)
   local xx = torch.repeatTensor(x, y:size(1),1)
   local yy = torch.repeatTensor(y:view(-1,1), 1, x:size(1))
   return xx, yy
end
Y, X = meshgrid(xx, yy)
U = -torch.pow(X,2) + Y -1
V =  X - torch.pow(Y,2) +1
speed = torch.sqrt(torch.cmul(U,U) + torch.cmul(V,V))
theta = torch.atan(torch.cdiv(V,U))

