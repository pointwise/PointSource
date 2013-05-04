if { ![namespace exists pw::_PtSrc] } {

package require PWI_Glyph 2.17.0

#####################################################################
#                       public namespace procs
#####################################################################
namespace eval pw::PtSrc {
}


#############################################################################
proc pw::PtSrc::getSelectType {} {
    array set selInfo { \
        2 Domain \
        3 Block \
    }
    return $selInfo([pw::Application getCAESolverDimension])
}

#############################################################################
proc pw::PtSrc::selectPoint { ptVarName {prompt "Select point"} } {
    upvar 1 $ptVarName pt
    set ret 1
    if { [catch {pw::Display selectPoint -description "$prompt"} pt] } {
        set ret 0
    }
    return $ret
}


########################################################################
proc pw::PtSrc::getSelection { selType selectedVarName errMsgVarName } {
    upvar 1 $selectedVarName selected
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
        # set selection based on current 2D/3D setting
        set mask [pw::Display createSelectionMask -require$selType Defined]
        if { ![pw::Display selectEntities \
                -description "Select one $selType" \
                -single \
                -selectionmask $mask \
                picks] } {
            set errMsg "$selType selection aborted!"
        } else {
            set selected $picks($selType\s)
            set ret 1
        }
    }
    return $ret
}


#############################################################################
proc pw::PtSrc::buildPointSource2 { ent centerPt ds growthRate numLayers } {
    for {set layer 0} {$layer < $numLayers} {incr layer} {
        buildNSLayer $centerPt $ds $growthRate $layer nsLayerPts
        set pointSource($layer) $nsLayerPts
    }
    lappend cons [pw::_PtSrc::createCon [list $centerPt [lindex $pointSource(0) 0]]]
    foreach {key ptList} [array get pointSource] {
        lappend cons [pw::_PtSrc::createCon $ptList]
    }
    return $cons
}


#############################################################################
proc pw::PtSrc::buildPointSource3 { ent centerPt ds growthRate numLayers } {
    for {set layer 0} {$layer < $numLayers} {incr layer} {
        # build NorthSouth layer pts
        pw::_PtSrc::buildNSLayer $centerPt $ds $growthRate $layer nsLayerPts
        # only need pts from north to south pole inclusive
        set nsLayerPts [lrange $nsLayerPts 0 [expr {[llength $nsLayerPts] / 2}]]
        set con1 [pw::_PtSrc::createCon $nsLayerPts]
        if { 0 == $layer } {
            # build semi-circle center dom
            set con2 [pw::_PtSrc::createCon [list [lindex $nsLayerPts 0] $centerPt [lindex $nsLayerPts end]]]
            lappend doms [pw::DomainUnstructured createFromConnectors [list $con1 $con2]]
        } else {
            # build dom between this and previous layer
            set con2 [pw::_PtSrc::createCon [list [lindex $nsLayerPts 0] [lindex $prevNsLayerPts 0]]]
            set con3 [pw::_PtSrc::createCon [list [lindex $nsLayerPts end] [lindex $prevNsLayerPts end]]]
            lappend doms [pw::DomainUnstructured createFromConnectors [list $con1 $con2 $con3 $prevNsCon]]
        }
        set prevNsCon $con1
        set prevNsLayerPts $nsLayerPts

        set numEwPts [expr {[llength $nsLayerPts] - 2}] ;# interior pts
        for {set jj 1} {$jj <= $numEwPts} {incr jj} {
            set nsPt [lindex $nsLayerPts $jj]
            # build EastWest layer pts
            pw::_PtSrc::buildEWLayer $centerPt $nsPt $ds $growthRate $layer ewLayerPts
            set ewMidCnt [expr {[llength $ewLayerPts] / 2}]
            set con1a [pw::_PtSrc::createCon [lrange $ewLayerPts 0 $ewMidCnt]]
            set con1b [pw::_PtSrc::createCon [lrange $ewLayerPts $ewMidCnt end]]
            if { 1 < $jj } {
                # build dom between this and previous layer
                set con2 [pw::_PtSrc::createCon [list [lindex $ewLayerPts 0] [lindex $prevEwLayerPts 0]]]
                set con3 [pw::_PtSrc::createCon [list [lindex $ewLayerPts $ewMidCnt] [lindex $prevEwLayerPts $prevEwMidCnt]]]
                set con4 [pw::_PtSrc::createCon [list [lindex $ewLayerPts end] [lindex $prevEwLayerPts end]]]
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
    set maxDs [pw::_PtSrc::calcLayerDs $ds $growthRate $numLayers]
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

    set cons [pw::_PtSrc::getUniqueDomCons $doms]
    pw::Connector join -reject unjoinedCons -keepDistribution $cons

    foreach dom $doms {
        set face [pw::FaceUnstructured create]
        $face addDomain $dom
        $face setBaffle true
        $ent addFace $face
    }

    return $doms
}
#####################################################################
#                       public namespace procs
#####################################################################
namespace eval pw::PtSrc {
}


#############################################################################
proc pw::PtSrc::getSelectType {} {
    array set selInfo { \
        2 Domain \
        3 Block \
    }
    return $selInfo([pw::Application getCAESolverDimension])
}

#############################################################################
proc pw::PtSrc::selectPoint { ptVarName {prompt "Select point"} } {
    upvar 1 $ptVarName pt
    set ret 1
    if { [catch {pw::Display selectPoint -description "$prompt"} pt] } {
        set ret 0
    }
    return $ret
}


########################################################################
proc pw::PtSrc::getSelection { selType selectedVarName errMsgVarName } {
    upvar 1 $selectedVarName selected
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
        # set selection based on current 2D/3D setting
        set mask [pw::Display createSelectionMask -require$selType Defined]
        if { ![pw::Display selectEntities \
                -description "Select one $selType" \
                -single \
                -selectionmask $mask \
                picks] } {
            set errMsg "$selType selection aborted!"
        } else {
            set selected $picks($selType\s)
            set ret 1
        }
    }
    return $ret
}


#############################################################################
proc pw::PtSrc::buildPointSource2 { ent centerPt ds growthRate numLayers } {
    for {set layer 0} {$layer < $numLayers} {incr layer} {
        buildNSLayer $centerPt $ds $growthRate $layer nsLayerPts
        set pointSource($layer) $nsLayerPts
    }
    lappend cons [pw::_PtSrc::createCon [list $centerPt [lindex $pointSource(0) 0]]]
    foreach {key ptList} [array get pointSource] {
        lappend cons [pw::_PtSrc::createCon $ptList]
    }
    return $cons
}


#############################################################################
proc pw::PtSrc::buildPointSource3 { ent centerPt ds growthRate numLayers } {
    for {set layer 0} {$layer < $numLayers} {incr layer} {
        # build NorthSouth layer pts
        pw::_PtSrc::buildNSLayer $centerPt $ds $growthRate $layer nsLayerPts
        # only need pts from north to south pole inclusive
        set nsLayerPts [lrange $nsLayerPts 0 [expr {[llength $nsLayerPts] / 2}]]
        set con1 [pw::_PtSrc::createCon $nsLayerPts]
        if { 0 == $layer } {
            # build semi-circle center dom
            set con2 [pw::_PtSrc::createCon [list [lindex $nsLayerPts 0] $centerPt [lindex $nsLayerPts end]]]
            lappend doms [pw::DomainUnstructured createFromConnectors [list $con1 $con2]]
        } else {
            # build dom between this and previous layer
            set con2 [pw::_PtSrc::createCon [list [lindex $nsLayerPts 0] [lindex $prevNsLayerPts 0]]]
            set con3 [pw::_PtSrc::createCon [list [lindex $nsLayerPts end] [lindex $prevNsLayerPts end]]]
            lappend doms [pw::DomainUnstructured createFromConnectors [list $con1 $con2 $con3 $prevNsCon]]
        }
        set prevNsCon $con1
        set prevNsLayerPts $nsLayerPts

        set numEwPts [expr {[llength $nsLayerPts] - 2}] ;# interior pts
        for {set jj 1} {$jj <= $numEwPts} {incr jj} {
            set nsPt [lindex $nsLayerPts $jj]
            # build EastWest layer pts
            pw::_PtSrc::buildEWLayer $centerPt $nsPt $ds $growthRate $layer ewLayerPts
            set ewMidCnt [expr {[llength $ewLayerPts] / 2}]
            set con1a [pw::_PtSrc::createCon [lrange $ewLayerPts 0 $ewMidCnt]]
            set con1b [pw::_PtSrc::createCon [lrange $ewLayerPts $ewMidCnt end]]
            if { 1 < $jj } {
                # build dom between this and previous layer
                set con2 [pw::_PtSrc::createCon [list [lindex $ewLayerPts 0] [lindex $prevEwLayerPts 0]]]
                set con3 [pw::_PtSrc::createCon [list [lindex $ewLayerPts $ewMidCnt] [lindex $prevEwLayerPts $prevEwMidCnt]]]
                set con4 [pw::_PtSrc::createCon [list [lindex $ewLayerPts end] [lindex $prevEwLayerPts end]]]
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
    set maxDs [pw::_PtSrc::calcLayerDs $ds $growthRate $numLayers]
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

    set cons [pw::_PtSrc::getUniqueDomCons $doms]
    pw::Connector join -reject unjoinedCons -keepDistribution $cons

    foreach dom $doms {
        set face [pw::FaceUnstructured create]
        $face addDomain $dom
        $face setBaffle true
        $ent addFace $face
    }

    return $doms
}


#####################################################################
#                       private namespace procs
#####################################################################
namespace eval pw::_PtSrc {
    variable PI
    set PI 3.141592653589793238462643383 ;# from www.joyofpi.com/pi.html

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
    proc distance { pt1 pt2 } {
        return [pwu::Vector3 length [pwu::Vector3 subtract $pt1 $pt2]]
    }


    #------------------------------------------------------------------------
    proc rotateX {v1 angle} {
        set mat [pwu::Transform rotation {1 0 0} $angle]
        pwu::Transform apply $mat $v1
    }


    #------------------------------------------------------------------------
    proc rotateY {v1 angle} {
        set mat [pwu::Transform rotation {0 1 0} $angle]
        pwu::Transform apply $mat $v1
    }


    #------------------------------------------------------------------------
    proc rotateZ {v1 angle} {
        set mat [pwu::Transform rotation {0 0 1} $angle]
        pwu::Transform apply $mat $v1
    }


    #------------------------------------------------------------------------
    proc buildLayer { axis centerPt ds layerOffset ptsVarName } {
        upvar $ptsVarName layerPts
        variable PI

        switch $axis {
        X {
            error "Unsupported axis '$axis'"
        }
        Y {
            set northPt [list -$layerOffset 0 0]
            set southPt [list $layerOffset 0 0]
        }
        Z {
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
        set numSegs [expr {round($PI * $layerOffset / $ds)}]
        set segAngle [expr {180.0 / $numSegs}]
        # Build layerPts around the origin. Offset them to centerPt later.
        set layerPts {}

        # Calc and capture northPt. It is always directly "above" origin
        lappend layerPts $northPt

        # Calc interior pts CCW between north and south pole pts.
        # The number of interior pts is $numSegs-1, so start at 1.
        set angle $segAngle
        for {set n 1} {$n < $numSegs} {incr n} {
            # rotate northPt about origin by angle degrees
            lappend layerPts [rotate$axis $northPt $angle]
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
            lappend layerPts [rotate$axis $northPt $angle]
        }

        # offset layerPts to the given centerPt
        for {set n 0} {$n < [llength $layerPts]} {incr n} {
            lset layerPts $n [pwu::Vector3 add [lindex $layerPts $n] $centerPt]
        }
    }


    #------------------------------------------------------------------------
    proc getUniqueDomCons { doms } {
        # use cons as array keys to eliminate duplicates
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
        # return array keys which are the unique cons
        return [array names conArray]
    }


    #------------------------------------------------------------------------
    proc buildNSLayer { centerPt ds growthRate layer ptsVarName } {
        upvar $ptsVarName layerPts

        # calc total radial distance from centerPt to layer
        set layerOffset [calcLayerOffset $ds $growthRate $layer]

        # scale starting ds to the layer's ds
        set ds [calcLayerDs $ds $growthRate $layer]

        buildLayer Z $centerPt $ds $layerOffset layerPts
    }


    #------------------------------------------------------------------------
    proc buildEWLayer { centerPt nsPt ds growthRate layer ptsVarName } {
        upvar $ptsVarName layerPts

        # move centerPt to the same y-plane as nsPt
        lset centerPt 1 [lindex $nsPt 1]

        # calc distance from centerPt to nsPt
        set layerOffset [distance $centerPt $nsPt]

        # scale starting ds to the layer's ds
        set ds [calcLayerDs $ds $growthRate $layer]

        buildLayer Y $centerPt $ds $layerOffset layerPts
        set layerPts [lrange $layerPts 1 end]
    }


    #------------------------------------------------------------------------
    proc createCon { pts } {
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
}

} ;# ![namespace exists pw::_PtSrc]
