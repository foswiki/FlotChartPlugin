# Plugin for Foswiki Collaboration Platform, http://Foswiki.org/
#
# (c)opyright SvenDowideit@fosiki.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::FlotChartPlugin;

use strict;
require Foswiki::Func;       # The plugins API
require Foswiki::Plugins;    # For the API version

use vars
  qw( $VERSION $RELEASE $SHORTDESCRIPTION $pluginName $NO_PREFS_IN_TOPIC
    $pluginJavascript
    $doneInit
    $ChartId 
    $mixedAlphaNum
  );

$VERSION = '$Rev$';
$RELEASE = '1.3';
$SHORTDESCRIPTION = 'A JQuery based CHARTs for Foswiki';
$NO_PREFS_IN_TOPIC = 1;

# Name of this Plugin, only used in this module
$pluginName = 'FlotChartPlugin';
$pluginJavascript = uc($pluginName) . '::JAVASCRIPT';


###############################################################################
sub initPlugin {

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 1.026 ) {
        Foswiki::Func::writeWarning(
            "Version mismatch between $pluginName and Plugins.pm");
        return 0;
    }

    # register new tags
    Foswiki::Func::registerTagHandler( 'FLOTCHART', \&_FLOTCHART );

    $doneInit = 0;

    return 1;
}

###############################################################################
sub doInit {
    return if $doneInit;
    $doneInit = 1;

    # init global vars
    $ChartId = 0;
    $mixedAlphaNum = Foswiki::Func::getRegularExpression('mixedAlphaNum');

    # add the initialisation javascript
    my $jscript = Foswiki::Func::readTemplate( lc($pluginName), 'javascript' );
    Foswiki::Func::addToZone('script', $pluginJavascript, $jscript, 'JQUERYPLUGIN' );

}

###############################################################################
sub expandVariables {
    my ($text, %params) = @_;

    return 0 unless $text;

    my $found = 0;

    foreach my $key (keys %params) {
        $found = 1 if $text =~ s/\$$key\b/$params{$key}/g;
    }

    $found = 1 if $text =~ s/\$percnt/\%/go;
    $found = 1 if $text =~ s/\$nop//go;
    $found = 1 if $text =~ s/\$n([^$mixedAlphaNum]|$)/\n$1/go;
    $found = 1 if $text =~ s/\$dollar/\$/go;

    $_[0] = $text if $found;

    return $found;
}

###############################################################################
sub _FLOTCHART {
    my ( $session, $params, $topic, $web ) = @_;

    doInit();

    my $seriesNames = $params->{_DEFAULT} || $params->{series};
    return unless ( defined($seriesNames) );

    # populate series hash
    my %seriesData;
    foreach my $name (split( /,/, $seriesNames )) {
        $name =~ s/^\s+//go;
        $name =~ s/\s+$//go;
        my $data = $params->{$name};
        next unless $data;
        $data = Foswiki::Func::expandCommonVariables($data, $topic, $web)
          if expandVariables($data);
        $seriesData{$name} = $data;
    }

    # create the plot options
    my @plotOptions = ();
    my $val;

    # xaxis
    my @xAxisOptions = ();
    $val  = $params->{xticks}; push @xAxisOptions, "ticks: [$val ]" if defined $val;
    $val = $params->{xmin}; push @xAxisOptions, "min: $val" if defined $val;
    $val = $params->{xmax}; push @xAxisOptions, "max: $val" if defined $val;
    $val = $params->{xmode}; push @xAxisOptions, "mode: '$val'" if defined $val;
    $val = $params->{xmargin}; push @xAxisOptions, "autoscaleMargin: $val" if defined $val;

    push @plotOptions, "xaxis : {".join(", ",@xAxisOptions)."}"
      if @xAxisOptions;

    # yaxis
    my @yAxisOptions = ();
    $val  = $params->{yticks}; push @yAxisOptions, "ticks: [$val]" if defined $val;
    $val = $params->{ymin}; push @yAxisOptions, "min: $val" if defined $val;
    $val = $params->{ymax}; push @yAxisOptions, "max: $val" if defined $val;
    $val = $params->{ymode}; push @yAxisOptions, "mode: '$val'" if defined $val;
    $val = $params->{ymargin}; push @yAxisOptions, "autoscaleMargin: $val" if defined $val;

    push @plotOptions, "yaxis : {".join(", ",@yAxisOptions)."}"
      if @yAxisOptions;

    my $options;
    $options = getOptions($params, 'points'); push @plotOptions, $options if $options;
    $options = getOptions($params, 'lines'); push @plotOptions, $options if $options;
    $options = getOptions($params, 'bars'); push @plotOptions, $options if $options;

    # canvas options
    my $width = $params->{width} || 'auto';
    my $height = $params->{height} || '300px';

    # gather series data
    my @jsVars   = ();
    my @flotData = ();
    foreach my $name ( keys(%seriesData) ) {
        push @jsVars, "var $name = [${seriesData{$name}}];";
        my @seriesOptions = ();
        my $label = $params->{"${name}_label"} || $name; 
        push @seriesOptions, "data: $name";
        push @seriesOptions, "label : '$label'";

        my $options;
        $options = getOptions($params, 'points', $name); push @seriesOptions, $options if $options;
        $options = getOptions($params, 'lines', $name); push @seriesOptions, $options if $options;
        $options = getOptions($params, 'bars', $name); push @seriesOptions, $options if $options;


        push @flotData, '{ ' . join(', ', @seriesOptions) . ' }';
    }

    my $jsVars = join("\n", @jsVars);
    my $flotData = join(",\n", @flotData);
    my $plotOptions = join(",\n", @plotOptions);

    $ChartId++;

    # format result
    my $result = <<'EOS';
<script id="flotChartSource%CHARTID%" language="javascript" type="text/javascript">
$(function () {
    %SERIES%
    var options = { %OPTIONS% };
    $.plot($("#flotChartPlaceholder%CHARTID%"), [ %SERIESNAMES% ], options);
});
</script>
EOS
    $result =~ s/%SERIES%/$jsVars/g;
    $result =~ s/%SERIESNAMES%/$flotData/g;
    $result =~ s/%OPTIONS%/$plotOptions/g;
    $result =~ s/%CHARTID%/$ChartId/g;
    $result =~ s/%WIDTH%/$width/g;
    $result =~ s/%HEIGHT%/$height/g;
    Foswiki::Func::addToZone('script', "!$pluginName - flotChart $ChartId", $result, $pluginJavascript );

    $result = <<'EOS';
<div class="flotChart" id="flotChartPlaceholder%CHARTID%" style="margin-top:1em;width:%WIDTH%;height:%HEIGHT%;"></div>
EOS
    $result =~ s/%SERIES%/$jsVars/g;
    $result =~ s/%SERIESNAMES%/$flotData/g;
    $result =~ s/%OPTIONS%/$plotOptions/g;
    $result =~ s/%CHARTID%/$ChartId/g;
    $result =~ s/%WIDTH%/$width/g;
    $result =~ s/%HEIGHT%/$height/g;
    $result =~ s/\s+$//go;

    return $result;
}

###############################################################################
sub getOptions {
    my ($params, $type, $name) = @_;

    $name ||= '';
    
    my $sep = $name?'_':'';
    my @options = ();
    my $val;

    $val = $params->{"${name}$sep${type}"}; push @options, "show: $val" if defined $val;
    $val = $params->{"${name}$sep${type}width"}; push @options, "lineWidth: $val" if defined $val;
    $val = $params->{"${name}$sep${type}fill"}; push @options, "fill: $val" if defined $val;
    $val = $params->{"${name}$sep${type}fillcolor"}; push @options, "fillColor: $val" if defined $val;
    $val = $params->{"${name}$sep${type}shadow"}; push @options, "shadowSize: $val" if defined $val;

    if ($type eq 'points') {
      $val = $params->{"${name}$sep${type}radius"}; push @options, "radius: $val" if defined $val;
    }

    if ($type eq 'bars') {
      $val = $params->{"${name}$sep${type}width"}; push @options, "barWidth: $val" if defined $val;
    }

    return undef unless @options;
    return "$type : { ".join(', ', @options)." }";
}

1;
