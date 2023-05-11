# Пример графика с интерактивным курсором
using CImGui
using CImGui: ImVec2, ImVec4
using ImPlot
using CSV
using DataFrames
using FileIO
using Plots
using ImPlot.LibCImGui: ImGuiCond_Once, ImGuiCond_Always, ImPlotAxisFlags_NoGridLines

include("src/Renderer.jl")
using .Renderer

include("src/readfiles.jl")
include("src/refmkpguifunctions.jl") 

const BINPATH = "data/bin/Noise Base"       # путь к папке с бинарями (должна существовать)
const BASEPATH = "data/raw mkp/Noise base"  # путь к папке с исходной разметкой (должна существовать)
const REFPATH = "data/new mkp/Noise base"   # путь к папке с изменённой разметкой (может не существовать)

mkpath(REFPATH) # создаём путь к папке с изменённой разметкой, если его не было

const FILENAMES = readdir(BASEPATH) # имена файлов базы

const SELECTED = Dict{String, Any}() # здесь храним информацию о выбранной записи, именах измерений в ней и выбранном измерении
SELECTED["file"] = 1    # задаём значения по умолчанию для старта 
SELECTED["record"] = 1
SELECTED["recordnames"] = readdir("$BASEPATH/$(FILENAMES[SELECTED["file"]])")

const RECORDDATA = Dict{String, Any}() # здесь храним прочитанную из выбранной записи информацию

mutable struct PlotBounds   # данные границ сегмента, рабочей зоны и АД (рз и ад - на накачке и на спуске)
    AD::NamedTuple{(:pump, :desc), NTuple{2, Bounds}}
    workreg::NamedTuple{(:pump, :desc), NTuple{2, Bounds}}
    segbounds::Bounds
end

mutable struct PlotState    # границы по осям для графика
    xlim::NamedTuple{(:min, :max), NTuple{2, Float32}}
    ylim::NamedTuple{(:min, :max), NTuple{2, Float32}}
end

const PLOTSTATE = Dict{String, Any}() # здесь храним состояние графика

# чтение записи
function read_record() 

    # чтение сигнала
    signals, fs, _, _ = readbin("$BINPATH/$(FILENAMES[SELECTED["file"]])")

    # чтение разметки (в приоритете - ранее изменённая. если такой не было - берём исходную)
    tone_mkp =  try ReadRefMkp("$REFPATH/$(FILENAMES[SELECTED["file"]])/$(SELECTED["record"])/tone.csv") 
                catch e 
                    ReadRefMkp("$BASEPATH/$(FILENAMES[SELECTED["file"]])/$(SELECTED["record"])/tone.csv") 
                end
    bnds =  try ReadRefMkp("$REFPATH/$(FILENAMES[SELECTED["file"]])/$(SELECTED["record"])/bounds.csv")
            catch e
                ReadRefMkp("$BASEPATH/$(FILENAMES[SELECTED["file"]])/$(SELECTED["record"])/bounds.csv")
            end

    plotbounds = PlotBounds((pump = bnds.iad.pump, desc = bnds.iad.desc), (pump = bnds.iwz.pump, desc = bnds.iwz.desc), bnds.segm)
    tone = signals.Tone[bnds.segm.ibeg:bnds.segm.iend] # берём из записи только сегмент, соответствующий выбранному измерению
    pres = signals.Pres[bnds.segm.ibeg:bnds.segm.iend] 

    RECORDDATA["tone"] = tone
    RECORDDATA["pres"] = pres
    RECORDDATA["fs"] = fs
    RECORDDATA["markup"] = tone_mkp

    PLOTSTATE["bounds"] = plotbounds
    PLOTSTATE["limits"] = PlotState((min = 1, max = lastindex(tone)), (min = minimum(tone)*1.2, max = maximum(tone)*1.2))
    PLOTSTATE["flag"] = ImGuiCond_Once
end

read_record() # читаем первый раз для запуска

# таблицы с именами файлов и именами измерений в выбранном файле
function FilesTable()

    # заголовки
    CImGui.TextColored(ImVec4(0.45, 0.7, 0.80, 1.00), "Имена файлов базы")
    CImGui.SameLine(CImGui.GetWindowContentRegionWidth()*0.52)
    CImGui.TextColored(ImVec4(0.45, 0.7, 0.80, 1.00), "Номера измерений в выбранной записи")

    # таблица с именами файлов
    CImGui.BeginChild("##filenames_scrollingregion", ImVec2(CImGui.GetWindowContentRegionWidth()*0.5, CImGui.GetWindowHeight()*0.7))
        CImGui.Columns(1, "Имена файлов")
        CImGui.Separator()

        for i in 1:lastindex(FILENAMES)
            if CImGui.Selectable(FILENAMES[i], i == SELECTED["file"])
                SELECTED["file"] = i
                SELECTED["recordnames"] = readdir("$BASEPATH/$(FILENAMES[SELECTED["file"]])")
                SELECTED["record"] = 1
                read_record()
            end
            CImGui.NextColumn()
            CImGui.Separator()
        end

    CImGui.EndChild()

    # таблица с именами измерений
    CImGui.SameLine(CImGui.GetWindowContentRegionWidth()*0.52)
    CImGui.BeginChild("##records_scrollingregion", ImVec2(CImGui.GetWindowContentRegionWidth(), CImGui.GetWindowHeight()*0.7))
        CImGui.Columns(1, "Номера измерений")
        CImGui.Separator()

        recordnames = SELECTED["recordnames"]

        for i in 1:lastindex(recordnames)
            if CImGui.Selectable(recordnames[i], i == SELECTED["record"])
                SELECTED["record"] = i
                read_record()
            end
            CImGui.NextColumn()
            CImGui.Separator()
        end
        CImGui.Columns(1)
    CImGui.EndChild()
end

# окно меню
function MenuWindow()
    CImGui.Begin("Меню")
        FilesTable()
    CImGui.End()
end

# захват курсора - выбираем, какая из четырёх границ ближе к точке, в которой случилось первое нажатие на график, чтобы до отпускания ЛКМ перемещать только эту границу
function CatchCursor()
    pt = ImPlot.GetPlotMousePos() # позиция мыши
    xpos = pt.x                   # позиция мыши по оси абсцисс

    bnd = PLOTSTATE["bounds"]     # берём актуальные границы
    p1, p2, p3, p4 = bnd.AD.pump.ibeg, bnd.AD.pump.iend, bnd.AD.desc.ibeg, bnd.AD.desc.iend
    crsr = [p1, p2, p3, p4] .* 1.0 # формируем из их вектор и переводим во float64

    moveind = ([abs(x - xpos) for x in crsr] |> findmin)[2] # ищем индекс курсора, ближайшего к позиции мыши

    PLOTSTATE["active cursor ind"] = moveind # сохраняем индекс курсора
end

# перемещение захваченного курсора
function MoveCursor()
    # ниже всё как в CatchCursor()
    pt = ImPlot.GetPlotMousePos()
    xpos = pt.x

    bnd = PLOTSTATE["bounds"]
    p1, p2, p3, p4 = bnd.AD.pump.ibeg, bnd.AD.pump.iend, bnd.AD.desc.ibeg, bnd.AD.desc.iend
    crsr = [p1, p2, p3, p4] .* 1.0

    # читаем индекс захваченного курсора и меяем его позицию на позицию мыши
    moveind = PLOTSTATE["active cursor ind"]
    crsr[moveind] = xpos 

    PLOTSTATE["bounds"].AD = (pump = Bounds(crsr[1], crsr[2]), desc = Bounds(crsr[3], crsr[4]))
end

# рисование графика
function MakePlot()

    tone = RECORDDATA["tone"]
    bnd = PLOTSTATE["bounds"]

    lims = PLOTSTATE["limits"]
    flag = PLOTSTATE["flag"]

    mkp = RECORDDATA["markup"]
    peaks = [x.pos for x in mkp]

    CImGui.PushID("$(SELECTED["file"])$(SELECTED["record"])") # закрепляем индивидуальный айдишник за каждым графиком, чтобы удобнее было работать с масштабами
        ImPlot.SetNextPlotLimits(lims.xlim.min, lims.xlim.max, lims.ylim.min, lims.ylim.max, flag)
        if ImPlot.BeginPlot("Тоны", C_NULL, C_NULL, ImVec2(CImGui.GetWindowContentRegionMax().x, CImGui.GetWindowContentRegionMax().y*0.8),
            x_flags = ImPlotAxisFlags_NoGridLines | ImPlotAxisFlags_NoDecorations, y_flags = ImPlotAxisFlags_NoGridLines)

            # рисуем сигнал тонов, его разметку и границы сад и дад
            ImPlot.PlotLine(tone, label_id = "Сигнал тонов")
            ImPlot.PlotScatter(peaks, tone[peaks])

            ImPlot.PlotVLines("САД и ДАД на накачке", [bnd.AD.pump.ibeg, bnd.AD.pump.iend], 2)
            ImPlot.PlotVLines("САД и ДАД на спуске", [bnd.AD.desc.ibeg, bnd.AD.desc.iend], 2)

            # флаг закрепления масштаба и перемещение курсоров зависят от действий мыши
            if ImPlot.IsPlotHovered() && CImGui.IsMouseClicked(0) # если навелись на график и нажали ЛКМ (при наведении на график и долгом нажатии ЛКМ этот флаг загорается первым и только один раз)
                PLOTSTATE["flag"] = ImGuiCond_Always # закрепляем масштаб
                CatchCursor()                        # определяем, какой курсор собираемся перемещать
            elseif ImPlot.IsPlotHovered() && CImGui.IsMouseDown(0) # навелись на график и зажали (и держим) ЛКМ (флаг горит всё время, пока зажата ЛКМ)
                PLOTSTATE["flag"] = ImGuiCond_Always # закрепляем масштаб
                MoveCursor()                         # двигаем выбранный в предыдущем условии курсор
            else
                PLOTSTATE["flag"] = ImGuiCond_Once   # в противном случае открепляем масштаб
            end

            limits = ImPlot.GetPlotLimits()       # сохраняем текущие лимиты графика по осям
            x1, x2 = limits.X.Min, limits.X.Max
            y1, y2 = limits.Y.Min, limits.Y.Max

            PLOTSTATE["limits"] = PlotState((min = x1, max = x2), (min = y1, max = y2))

            if ImPlot.IsPlotHovered() && CCImGui.IsMouseDoubleClicked(0) # при двойном нажатии ЛКМ на графике возвращаем его исходный масштаб
                PLOTSTATE["limits"] = PlotState((min = 1, max = lastindex(tone)), (min = minimum(tone)*1.2, max = maximum(tone)*1.2))
            end

            ImPlot.EndPlot()
        end
    CImGui.PopID()
end

function to_int(obj::Bounds)
    obj.ibeg = round(Int, obj.ibeg)
    obj.iend = round(Int, obj.iend)

    return obj
end

# сохранение изменённой разметки
function SaveButton() 
    if CImGui.Button("Сохранить границы")
        bnd = PLOTSTATE["bounds"]
        segbounds = bnd.segbounds
        ad = (pump = to_int(bnd.AD.pump), desc = to_int(bnd.AD.desc))
        wz = (pump = bnd.workreg.pump, desc = bnd.workreg.desc)

        path = "$REFPATH/$(FILENAMES[SELECTED["file"]])/$(SELECTED["record"])"
        mkpath(path)

        SaveRefMarkup("$path/tone.csv", RECORDDATA["markup"])
        SaveRefMarkup("$path/bounds.csv", RECORDDATA["pres"], segbounds, ad, wz) 
    end
end

# окно с графком
function PlotWindow()
    CImGui.Begin("График")
        SaveButton()
        MakePlot()
    CImGui.End()
end

# собираем все окна
function ui()
    MenuWindow()
    PlotWindow()
end

function show_gui()
    Renderer.render(
        ()->ui(),
        width = 1800,
        height = 1000,
        title = "",
        v = Renderer.GR()
    )
end

show_gui();