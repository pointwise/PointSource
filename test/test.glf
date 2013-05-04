package require PWI_Glyph 2.17.0

source [file join [file dirname [info script]] "../pointsource.glf"]


#####################################################################
proc getSettings { selectedVarName centerPtVarName dsVarName errMsgVarName } {
    upvar 1 $selectedVarName selected
    upvar 1 $centerPtVarName centerPt
    upvar 1 $dsVarName ds
    upvar 1 $errMsgVarName errMsg
	set selType [pw::PtSrc::getSelectType]
    set ret 0
	if { ![pw::PtSrc::getSelection $selType selected errMsg] } {
		set errMsg "$selType selection aborted!"
	} elseif { ![pw::PtSrc::selectPoint centerPt "Select point source location"] } {
		set errMsg "Center point selection aborted!"
	} elseif { ![pw::PtSrc::selectPoint dsPt "Select point on the first layer to define the initial ds."] } {
		set errMsg "ds point selection aborted!"
	} else {
		set ds [pwu::Vector3 length [pwu::Vector3 subtract $dsPt $centerPt]]
		set ret 1
	}
    return $ret
}


#####################################################################
#####################################################################
#####################################################################
#####################################################################

set growthRate 1.3
set numLayers 5
set dim [pw::Application getCAESolverDimension]

if { [getSettings ent centerPt ds errMsg] } {
    puts "---------------------------"
    puts "dim       : $dim"
    puts "ds        : $ds"
    puts "growthRate: $growthRate"
    puts "numLayers : $numLayers"
    puts "centerPt  : $centerPt"
    puts "---------------------------"

    set ptSrcEnts [pw::PtSrc::buildPointSource$dim $ent $centerPt $ds $growthRate $numLayers]

    puts "Initializing [$ent getName]..."
	set solver [pw::Application begin UnstructuredSolver [list $ent]]
	$solver run Initialize
	$solver end
	unset solver
    puts "Initialization complete"

	pw::Entity cycleColors $ptSrcEnts
	foreach ptSrcEnt $ptSrcEnts {
		$ptSrcEnt setRenderAttribute FillMode Shaded
	}
} else {
    puts "ERROR: $errMsg"
}
