package require PWI_Glyph 2.17.0

set disableAutoRun_PtSrc 1
source [file join [file dirname [info script]] "../pointsource.glf"]

pw::Application reset -keep Clipboard
set mode [pw::Application begin ProjectLoader]
$mode initialize [file join [file dirname [info script]] "grid3D.pw"]
$mode setAppendMode false
$mode load
$mode end
unset mode

set blk [pw::Grid getByName "blk-1"]
pw::PtSrc::buildPointSource3 $blk {13.546179 12.470546  7.7679454} [pw::Grid getByName "conSrcLong"]
pw::PtSrc::buildPointSource3 $blk { 5.332094 15.398518  9.642831} [pw::Grid getByName "conSrcMed"]
pw::PtSrc::buildPointSource3 $blk {15.465834  5.848467 14.472941} [pw::Grid getByName "conSrcShort"]

set ds         0.1
set growthRate 1.3
set numLayers  5
set layerData [pw::PtSrc::buildLayerData $ds $growthRate $numLayers]
pw::PtSrc::doBuildPointSource3 $blk {5.7240054 5.5270587 14.472941} $layerData
