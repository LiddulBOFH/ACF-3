local Storyboard = Ponder.API.NewStoryboard("acf", "tankextras", "waterjets")
Storyboard:WithName("Waterjets")
Storyboard:WithModelIcon("models/maxofs2d/thruster_propeller.mdl")
Storyboard:WithDescription("Learn the basics of waterjets.")
Storyboard:WithIndexOrder(0)

-------------------------------------------------------------------------------------------------
local Chapter = Storyboard:Chapter("Setup")
Chapter:AddInstruction("MoveCameraLookAt", {Length = 1,  Angle = -225, Distance = 2000}):DelayByLength()

Chapter:AddDelay(Chapter:AddInstruction("PlaceModels", {
    Length = 0.5,
    Models = {
        {Name = "Base", IdentifyAs = "Base", Model = "models/hunter/plates/plate2x5.mdl", Angles = Angle(0, 0, 0), Position = Vector(0, 0, 0), ComeFrom = Vector(0, 0, 50), Scale = Vector(1, 1.25, 1), },
        {Name = "Engine", IdentifyAs = "Engine", Model = "models/engines/v12l.mdl", Angles = Angle(0, 90, 0), Position = Vector(0, 100, 3), ComeFrom = Vector(0, 0, 50), ParentTo = "Base", },
        {Name = "Gearbox", IdentifyAs = "Gearbox", Model = "models/engines/t5small.mdl", Angles = Angle(0, -180, 0), Position = Vector(0, -50, 5), ComeFrom = Vector(0, 0, 50), ParentTo = "Base", Scale = Vector(2, 2, 2)},
        {Name = "FuelTank1", IdentifyAs = "Fuel Tank", Model = "models/holograms/hq_rcube.mdl", Angles = Angle(0, -90, 0), Position = Vector(36, 100, 15), ComeFrom = Vector(0, 0, 50), Scale = Vector(6, 2, 2), Material = "models/props_canal/metalcrate001d", ParentTo = "Base", },
        {Name = "FuelTank2", IdentifyAs = "Fuel Tank", Model = "models/holograms/hq_rcube.mdl", Angles = Angle(0, -90, 0), Position = Vector(-36, 100, 15), ComeFrom = Vector(0, 0, 50), Scale = Vector(6, 2, 2), Material = "models/props_canal/metalcrate001d", ParentTo = "Base", },
    }
}))

local Chapter = Storyboard:Chapter("Water Jet Placement")

Chapter:AddDelay(Chapter:AddInstruction("Caption", {Text = "Make sure your water jet is underwater to function properly."}))
Chapter:AddDelay(Chapter:AddInstruction("PlaceModels", {
    Length = 0.5,
    Models = { {Name = "Water Jet", IdentifyAs = "Water Jet", Model = "models/maxofs2d/thruster_propeller.mdl", Angles = Angle(90, -90, 0), Position = Vector(0, -140, -15), ComeFrom = Vector(0, 0, 50), Scale = Vector(1.5, 1.5, 1.5), Material = "models/maxofs2d/thruster_propeller.mdl", ParentTo = "Base", },
    }
}))

Chapter:AddDelay(1)

local Chapter = Storyboard:Chapter("Linking Components")

Chapter:AddInstruction("ShowToolgun", {Tool = language.GetPhrase("tool.acf_menu.menu_name")}):DelayByLength()

Chapter:AddDelay(Chapter:AddInstruction("Caption", {Text = "Right click the engine and right click the gearbox to link them together."}))

Chapter:AddDelay(Chapter:AddInstruction("ACF Menu", {
    Children = {"Engine"},
    Target = "Gearbox",
    Easing = math.ease.InOutQuad,
    Length = 2,
}))

Chapter:AddDelay(Chapter:AddInstruction("Caption", {Text = "Now the gearbox can receive power from the engine."}))

Chapter:AddDelay(Chapter:AddInstruction("Caption", {Text = "Right click the gearbox and right click the water jet to link them together."}))

Chapter:AddDelay(Chapter:AddInstruction("ACF Menu", {
    Children = {"Gearbox"},
    Target = "Water Jet",
    Easing = math.ease.InOutQuad,
    Length = 2,
}))

local Chapter = Storyboard:Chapter("Yaw Control")

Chapter:AddDelay(Chapter:AddInstruction("Caption", {Text = "Your water jet now propels you forward. To make it turn your vehicle wire the Yaw input on your water jet to a value between -1 and 1. "}))

Chapter:AddInstruction("HideToolgun", {}):DelayByLength()