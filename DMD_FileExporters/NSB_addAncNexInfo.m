function nexEventStruct = NSB_addAncNexInfo(nexEventStruct,node,nEvents,type)
% addAncInfo is a helper function to add structure fields that the
% Neuroexplorer file requires to be written.  
%
% Usage:
%  >> nexEventStruct = addAncInfo(nexEventStruct,node,nEvents,type)
%
% Inputs:
%   nexEventStruct   - STRUCT of Nex Data;
%   node             - Structure Node Index to add data;
%   nEvents          - Number of events (timestamps) in that Node
%   type             - Nex Data Type (0-Neuron; 1-Event; 2-Interval; 3-Waveform; 4-Population Vector; 5-Continuous Variable; 6-Marker)
%
% Outputs:
%   nexEventStruct   - Appended nexEventStruct.
%
% See also: 
%
% Copyright (C) 2010 by David Devilbiss <david.devilbiss@NexStepBiormarkers.com>
%  v. 1.0 DMD 10Oct2010
%
% ToDo: Add Neuroexplorer Specs for Waveform, Continuous, and Population vector to
% calculate ADtoMV and MVoffset
%

if nargin < 4
    type = 1;
end
nexEventStruct(node,1).type = type;
nexEventStruct(node,1).varVersion = 100;
nexEventStruct(node,1).FilePosDataOffset = -1;
nexEventStruct(node,1).nEvents = nEvents;
nexEventStruct(node,1).WireNumber = 0;
nexEventStruct(node,1).UnitNumber = 0;
nexEventStruct(node,1).Gain = 0;
nexEventStruct(node,1).Filter = 0;
nexEventStruct(node,1).XPos = 0;
nexEventStruct(node,1).YPos = 0;
nexEventStruct(node,1).WFrequency = 0;
nexEventStruct(node,1).ADtoMV = 0;
nexEventStruct(node,1).NPointsWave = 0;
nexEventStruct(node,1).NMarkers = 0;
nexEventStruct(node,1).MarkerLength = 0;
nexEventStruct(node,1).MVOfffset = 0;    