# glyph-pointsource
A Glyph script for inserting a 2D or 3D point source into a grid.

![Point Source Example Image][1]

[1]: https://raw.github.com/dbgarlisch/glyph-pointsource/master/ScriptImage.png  "Point Source Example Image"


## Generating Geometry
This script inserts a point source into an existing grid block or domain.

The script detects the grid's CAE dimensionality and prompts for input
accordingly.

In 2D, the point source is built as a collection of unclosed, concentric,
circular connectors centered around a user-defined location. An additional,
two-point connector is created to capture the center point. These connectors are
inserted into a user-selected domain as interior edges.

In 3D, the point source is built as a collection of unclosed, concentric,
spherical domains centered around a user-defined location. An additional,
half-disk domain is created to capture the unused seam points. These domains are
inserted into a user-selected block as interior baffles.

For both 2D and 3D, the point source layer spacing is controlled using a
connector's distribution. One point source layer will be create for each
connector point *except* for the first. The connector must exist before running
the script.

### Limitations
* The script does *not* check if a point source pierces a boundary of the targeted block or domain.
* 2D point sources are built in an XY plane.

## Running The Script

* Build or open the grid into which you want to insert a point source.
* Execute this script.
* Select the Block/Domain target into which you want to insert the point source.
  However, if the grid only contains a single target, it will be used
  automatically.
* Select point source location. You can select any existing grid point (it is
  often simpler to select the starting point of the connector selected in the
  next step).
* Select the connector to use for the point source layer spacing.
* Wait for the script to finish.


## Sourcing This Script

It is possible to source this script in your own Glyph scripts and use it as a library.

To source this script add the following lines to your script:

    set disableAutoRun_PtSrc 1 ;# disable the autorun
    source "/some/path/to/your/copy/of/pointsource.glf"]

See the scripts `test/test2D.glf` and `test/test3D.glf` for examples.


### pw::PtSrc Library Docs

#### proc pw::PtSrc::buildLayerData { ds growthRate numLayers }
Build a point source layer data list using an initial spacing, growth
    rate and number of layers.

    ds         - Initial layer spacing (float).
    growthRate - Layer spacing growth rate (float).
    numLayers  - Number of concentric layers (integer).

#### proc pw::PtSrc::buildLayerDataFromCon { con }
Build a point source layer data list using a connector.

    con - A pointwise connector object.

#### proc pw::PtSrc::doBuildPointSource2 { dom centerPt layerData }
Build a 2D point source using a layer data list.

    dom       - A pointwise domain object.
    centerPt  - The center point {x y z}.
    layerData - The layer spacing list {{r0 ds0} ... {rN dsN}}.

#### proc pw::PtSrc::buildPointSource2 { dom centerPt con }
Build a 2D point source using a connector.

    dom      - A pointwise domain object.
    centerPt - The center point {x y z}.
    con      - A pointwise connector object.

#### proc pw::PtSrc::doBuildPointSource3 { blk centerPt layerData }
Build a 3D point source using a layer data list.

    blk       - A pointwise block object.
    centerPt  - The center point {x y z}.
    layerData - The layer spacing list {{r0 ds0} ... {rN dsN}}.

#### proc pw::PtSrc::buildPointSource3 { blk centerPt con }
Build a 3D point source using a connector.

    blk       - A pointwise block object.
    centerPt  - The center point {x y z}.
    con      - A pointwise connector object.


### pw::PtSrc Library Usage Examples

#### Creating a 2D Point Source Using a Connector
    set dom [pw::Grid getByName "dom-1"]
    set pt {13.546179 12.470546  7.7679454}
    set con [pw::Grid getByName "con-1"]
    pw::PtSrc::buildPointSource2 $dom $pt $con

#### Creating a 2D Point Source Using Initial Spacing, Growth Rate and Number of Layers
    set ds         0.1
    set growthRate 1.3
    set numLayers  5
    set layerData [pw::PtSrc::buildLayerData $ds $growthRate $numLayers]

    set dom [pw::Grid getByName "dom-1"]
    set pt {5.7 5.5 14.4}
    pw::PtSrc::doBuildPointSource2 $dom $pt $layerData

#### Creating a 3D Point Source Using a Connector
    set blk [pw::Grid getByName "blk-1"]
    set pt {13.546179 12.470546  7.7679454}
    set con [pw::Grid getByName "con-1"]
    pw::PtSrc::buildPointSource3 $blk $pt $con

#### Creating a 3D Point Source Using Initial Spacing, Growth Rate and Number of Layers
    set ds         0.1
    set growthRate 1.3
    set numLayers  5
    set layerData [pw::PtSrc::buildLayerData $ds $growthRate $numLayers]

    set blk [pw::Grid getByName "blk-1"]
    set pt {5.7 5.5 14.4}
    pw::PtSrc::doBuildPointSource3 $blk $pt $layerData


## Disclaimer
Scripts are freely provided. They are not supported products of
Pointwise, Inc. Some scripts have been written and contributed by third
parties outside of Pointwise's control.

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, POINTWISE DISCLAIMS
ALL WARRANTIES, EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED
TO, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE, WITH REGARD TO THESE SCRIPTS. TO THE MAXIMUM EXTENT PERMITTED
BY APPLICABLE LAW, IN NO EVENT SHALL POINTWISE BE LIABLE TO ANY PARTY
FOR ANY SPECIAL, INCIDENTAL, INDIRECT, OR CONSEQUENTIAL DAMAGES
WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF BUSINESS
INFORMATION, OR ANY OTHER PECUNIARY LOSS) ARISING OUT OF THE USE OF OR
INABILITY TO USE THESE SCRIPTS EVEN IF POINTWISE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES AND REGARDLESS OF THE FAULT OR NEGLIGENCE OF
POINTWISE.
