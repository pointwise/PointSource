package require PWI_Glyph 2.17.0

source [file join [file dirname [info script]] "../vec/vec.tcl"]


#####################################################################
namespace eval pwps {

    #------------------------------------------------------------------------
    proc calcLayerOffset { ds growthRate layer } {
		set R 1.0
		for {set ii 1} {$ii <= $layer} {incr ii} {
			set R [expr {$R + ( $growthRate ** $ii )}]
		}
		return [expr {$R * $ds}]
    }


    #------------------------------------------------------------------------
    proc calcLayerDs { ds growthRate layer } {
		return [expr {$ds * ( $growthRate ** $layer ) }]
    }


    #------------------------------------------------------------------------
    proc buildLayer { axis centerPt ds layerOffset ptsVarName } {
		upvar $ptsVarName layerPts

		switch $axis {
		x {
			error "Illegal axis '$axis'"
		}
		y {
			set northPt [list -$layerOffset 0 0]
			set southPt [list $layerOffset 0 0]
		}
		z {
			set northPt [list 0 $layerOffset 0]
			set southPt [list 0 -$layerOffset 0]
		}
		default {
			error "Illegal axis '$axis'"
		}
		}

		# calc numSegs by dividing half circumfrence (PI * layerOffset) by ds and
		# round to the nearest int. This will give segment arc lengths as close as
		# possible to the desired layer ds
		set numSegs [expr {round($vec::PI * $layerOffset / $ds)}]
		set segAngle [expr {$vec::PI / $numSegs}]

		# Build layerPts around the origin. Offset them to centerPt later.
		set layerPts {}

		# Calc and capture northPt. It is always directly "above" origin
		lappend layerPts $northPt

		# Calc interior pts CCW between north and south pole pts.
		# The number of interior pts is $numSegs-1, so start at 1.
		set angle $segAngle
		for {set n 1} {$n < $numSegs} {incr n} {
			# rotate northPt about origin by angle degrees
			lappend layerPts [vec::rot$axis $northPt $angle]
			set angle [expr {$angle + $segAngle}]
		}

		# Append south pole pt. It is always directly "below" center
		lappend layerPts $southPt

		# Calc interior pts CCW between south and north pole pts.
		# The number of interior pts is $numSegs-1, so start at 1.
		# Use angle as left by loop above.
		for {set n 1} {$n < $numSegs} {incr n} {
			# pre incr to skip past south pole pt calc'ed above
			set angle [expr {$angle + $segAngle}]
			# rotate northPt about origin by angle degrees
			lappend layerPts [vec::rot$axis $northPt $angle]
		}

		# offset layerPts to the given centerPt
		for {set n 0} {$n < [llength $layerPts]} {incr n} {
			lset layerPts $n [vec::add [lindex $layerPts $n] $centerPt]
		}
    }
}

#############################################################################
proc pwps::getSelectType {} {
    array set selInfo { \
        2 Domain \
        3 Block \
    }
    return $selInfo([pw::Application getCAESolverDimension])
}

#############################################################################
proc pwps::selectPoint { ptVarName {prompt "Select point"} } {
    upvar 1 $ptVarName pt
    set ret 1
    if { [catch {pw::Display selectPoint -description "$prompt"} pt] } {
        set ret 0
    }
    return $ret
}


########################################################################
proc pwps::getSelection { selType selectedVarName centerPtVarName dsVarName errMsgVarName } {
    upvar 1 $selectedVarName selected
    upvar 1 $centerPtVarName centerPt
    upvar 1 $dsVarName ds
    upvar 1 $errMsgVarName errMsg
    array set validSelTypes { \
        Connector 0 \
        Domain    1 \
        Block     2 \
        Database  3 \
        Spacing   4 \
        Boundary  5 \
    }
    set ret 0
    set selected {}

    set allEnts [pw::Grid getAll -type "pw::$selType"]
    set gridCnt 0
    foreach ent $allEnts {
        if { [$ent getEnabled] && [pw::Display isLayerVisible [$ent getLayer]] } {
            incr gridCnt
            lappend selected $ent
        }
    }

    if { "" == [array get validSelTypes $selType] } {
        set errMsg "Invalid Selection Type '$selType'"
    } elseif { 0 == $gridCnt } {
        set errMsg "No appropriate $selType entities are available for selection!"
    } elseif { 1 == $gridCnt } {
        # force selection of only $selType ent available
        set ret 1
    } else {
        #puts "$selType gridCnt=$gridCnt"
        # set selection based on current 2D/3D setting
        set mask [pw::Display createSelectionMask -require$selType Defined]
        if { ![pw::Display selectEntities \
                -description "Select one $selType" \
                -single \
                -selectionmask $mask \
                picks] } {
            set errMsg "$selType selection aborted!"
        } elseif { ![pwps::selectPoint centerPt "Select point source location"] } {
            set errMsg "Center point selection aborted!"
        } elseif { ![pwps::selectPoint dsPt "Select point on the first layer to define the initial ds."] } {
            set errMsg "ds point selection aborted!"
        } else {
            set ds [pwu::Vector3 length [pwu::Vector3 subtract $dsPt $centerPt]]
            set selected $picks($selType\s)
            set ret 1
        }
    }
    return $ret
}


#############################################################################
proc pwps::buildNSLayer { centerPt ds growthRate layer ptsVarName } {
    upvar $ptsVarName layerPts

    # calc total radial distance from centerPt to layer
    set layerOffset [calcLayerOffset $ds $growthRate $layer]

    # scale starting ds to the layer's ds
    set ds [calcLayerDs $ds $growthRate $layer]

    buildLayer z $centerPt $ds $layerOffset layerPts
}


#############################################################################
proc pwps::buildEWLayer { centerPt nsPt ds growthRate layer ptsVarName } {
    upvar $ptsVarName layerPts

    # move centerPt to the same y-plane as nsPt
    lset centerPt 1 [lindex $nsPt 1]

    # calc distance from centerPt to nsPt
    set layerOffset [vec::dist $centerPt $nsPt]

    # scale starting ds to the layer's ds
    set ds [calcLayerDs $ds $growthRate $layer]

    buildLayer y $centerPt $ds $layerOffset layerPts
	set layerPts [lrange $layerPts 1 end]
}


#############################################################################
proc pwps::createCon { pts } {
	set seg [pw::SegmentSpline create]
	foreach pt $pts {
		$seg addPoint $pt
	}
	$seg setSlope CatmullRom
	set con [pw::Connector create]
	$con addSegment $seg
	$con setDimension [llength $pts]
	#$con setRenderAttribute PointMode All
	unset seg
	return $con
}


#############################################################################
proc pwps::buildPointSource2 { ent centerPt ds growthRate numLayers } {
	for {set layer 0} {$layer < $numLayers} {incr layer} {
		buildNSLayer $centerPt $ds $growthRate $layer nsLayerPts
		set pointSource($layer) $nsLayerPts
	}
	createCon [list $centerPt [lindex $pointSource(0) 0]]
	foreach {key ptList} [array get pointSource] {
		createCon $ptList
	}
}


#############################################################################
proc pwps::getUniqueDomCons { doms } {
	array set conArray {}
	foreach dom $doms {
		set numEdges [$dom getEdgeCount]
		for {set ii 1} {$ii <= $numEdges} {incr ii} {
			set edge [$dom getEdge $ii]
			set numCons [$edge getConnectorCount]
			for {set jj 1} {$jj <= $numCons} {incr jj} {
				set conArray([$edge getConnector $jj]) 1
			}
		}
	}
	return [array names conArray]
}


#############################################################################
proc pwps::buildPointSource3 { ent centerPt ds growthRate numLayers } {
	for {set layer 0} {$layer < $numLayers} {incr layer} {
		# build NorthSouth layer pts
		pwps::buildNSLayer $centerPt $ds $growthRate $layer nsLayerPts
		# only need pts from north to south pole inclusive
		set nsLayerPts [lrange $nsLayerPts 0 [expr {[llength $nsLayerPts] / 2}]]
		set con1 [createCon $nsLayerPts]
		if { 0 == $layer } {
			# build semi-circle center dom
			set con2 [createCon [list [lindex $nsLayerPts 0] $centerPt [lindex $nsLayerPts end]]]
			lappend doms [pw::DomainUnstructured createFromConnectors [list $con1 $con2]]
		} else {
			# build dom between this and previous layer
			set con2 [createCon [list [lindex $nsLayerPts 0] [lindex $prevNsLayerPts 0]]]
			set con3 [createCon [list [lindex $nsLayerPts end] [lindex $prevNsLayerPts end]]]
			lappend doms [pw::DomainUnstructured createFromConnectors [list $con1 $con2 $con3 $prevNsCon]]
		}
		set prevNsCon $con1
		set prevNsLayerPts $nsLayerPts
		#set dom [pw::DomainUnstructured createFromConnectors [list $_CN(12) $_CN(13) $_CN(14) $_CN(19)]]

		set numEwPts [expr {[llength $nsLayerPts] - 2}] ;# interior pts
		for {set jj 1} {$jj <= $numEwPts} {incr jj} {
			set nsPt [lindex $nsLayerPts $jj]
			# build EastWest layer pts
			pwps::buildEWLayer $centerPt $nsPt $ds $growthRate $layer ewLayerPts
			set ewMidCnt [expr {[llength $ewLayerPts] / 2}]
			set con1a [createCon [lrange $ewLayerPts 0 $ewMidCnt]]
			set con1b [createCon [lrange $ewLayerPts $ewMidCnt end]]
			if { 1 < $jj } {
				# build dom between this and previous layer
				set con2 [createCon [list [lindex $ewLayerPts 0] [lindex $prevEwLayerPts 0]]]
				set con3 [createCon [list [lindex $ewLayerPts $ewMidCnt] [lindex $prevEwLayerPts $prevEwMidCnt]]]
				set con4 [createCon [list [lindex $ewLayerPts end] [lindex $prevEwLayerPts end]]]
				lappend doms [pw::DomainUnstructured createFromConnectors [list $con1a $con2 $con3 $prevEwCon1a]]
				lappend doms [pw::DomainUnstructured createFromConnectors [list $con1b $con3 $con4 $prevEwCon1b]]
			}
			set prevEwCon1a $con1a
			set prevEwCon1b $con1b
			set prevEwMidCnt $ewMidCnt
			set prevEwLayerPts $ewLayerPts
		}
	}

    # run solver on doms using a large min edge length to prevent insertion of
    # interior points. Do this before joining to preserve the edge point positions.
	set maxDs [calcLayerDs $ds $growthRate $numLayers]
	set colxn [pw::Collection create]
	$colxn set $doms
	$colxn do setUnstructuredSolverAttribute EdgeMinimumLength [expr {$maxDs * 10}]
	$colxn delete
	unset colxn
	set solver [pw::Application begin UnstructuredSolver $doms]
	$solver run Initialize
	$solver end
	unset solver

	set doms [pw::DomainUnstructured join -reject unjoinedDoms $doms]
	append doms $unjoinedDoms

	set cons [pwps::getUniqueDomCons $doms]
	pw::Connector join -reject unjoinedCons -keepDistribution $cons

	pw::Entity cycleColors $doms
	foreach dom $doms {
        set face [pw::FaceUnstructured create]
        $face addDomain $dom
        $face setBaffle true
        $ent addFace $face
		$dom setRenderAttribute FillMode Shaded
	}
    return $doms
}

#####################################################################
#####################################################################
#####################################################################
#####################################################################

#set ds 0.4
set growthRate 1.1
set numLayers 10
#set centerPt {10 10 10}
set dim [pw::Application getCAESolverDimension]
set selType [pwps::getSelectType]


if { [pwps::getSelection $selType ent centerPt ds errMsg] } {
    puts "---------------------------"
    puts "dim       : $dim"
    puts "selectType: $selType"
    puts "ds        : $ds"
    puts "growthRate: $growthRate"
    puts "numLayers : $numLayers"
    puts "centerPt  : $centerPt"
    puts "---------------------------"
    puts ""
    pwps::buildPointSource$dim $ent $centerPt $ds $growthRate $numLayers
    # resolve block
    puts "Initializing $selType [$ent getName]..."
	set solver [pw::Application begin UnstructuredSolver [list $ent]]
	$solver run Initialize
	$solver end
	unset solver
    puts "Initializing complete"
    #pw::Display resetView
} else {
    puts "ERROR: $errMsg"
}
