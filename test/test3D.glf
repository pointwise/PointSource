#############################################################################
#
# (C) 2021 Cadence Design Systems, Inc. All rights reserved worldwide.
#
# This sample script is not supported by Cadence Design Systems, Inc.
# It is provided freely for demonstration purposes only.
# SEE THE WARRANTY DISCLAIMER AT THE BOTTOM OF THIS FILE.
#
#############################################################################

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

#############################################################################
#
# This file is licensed under the Cadence Public License Version 1.0 (the
# "License"), a copy of which is found in the included file named "LICENSE",
# and is distributed "AS IS." TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE
# LAW, CADENCE DISCLAIMS ALL WARRANTIES AND IN NO EVENT SHALL BE LIABLE TO
# ANY PARTY FOR ANY DAMAGES ARISING OUT OF OR RELATING TO USE OF THIS FILE.
# Please see the License for the full text of applicable terms.
#
#############################################################################
