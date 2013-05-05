package require PWI_Glyph 2.17.0

set disableAutoRun_PtSrc 1
source [file join [file dirname [info script]] "../pointsource.glf"]

pw::Application reset -keep Clipboard
set mode [pw::Application begin ProjectLoader]
$mode initialize [file join [file dirname [info script]] "grid2D.pw"]
$mode setAppendMode false
$mode load
$mode end
unset mode

set dom [pw::Grid getByName "dom-1"]
pw::PtSrc::buildPointSource2 $dom {5.3172775 13.790404 0.0} [pw::Grid getByName "conSrcLong"]
pw::PtSrc::buildPointSource2 $dom {14.425223 14.138317 0.0} [pw::Grid getByName "conSrcMed"]
pw::PtSrc::buildPointSource2 $dom {9.6508701 5.8207689 0.0} [pw::Grid getByName "conSrcShort"]

set ds         0.09
set growthRate 1.3
set numLayers  5
set layerData [pw::PtSrc::buildLayerData $ds $growthRate $numLayers]
pw::PtSrc::doBuildPointSource2 $dom {16.437868 4.2601904 0.0} $layerData
