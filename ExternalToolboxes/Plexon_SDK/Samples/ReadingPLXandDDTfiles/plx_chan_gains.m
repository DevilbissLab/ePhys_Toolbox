function [gains] = plx_chan_gains(filename)
% plx_chan_gains(filename) Read channel gains from a .plx file header
%
% [gains] = plx_chan_gains(filename)
%
% INPUT:
%   filename - if empty string, will use File Open dialog
% OUTPUT:
%   gains - array of gains, one per channel
%
if(nargin ~= 1)
   disp('1 input argument is required')
   return
end

gains = 0;

if(length(filename) == 0)
   [fname, pathname] = uigetfile('*.plx', 'Select a plx file');
	filename = strcat(pathname, fname);
end

fid = fopen(filename, 'r');
if(fid == -1)
	disp('cannot open file');
   return
end

disp(strcat('file = ', filename));

% read file header
header = fread(fid, 64, 'int32');
freq = header(35);  % frequency
ndsp = header(36);  % number of dsp channels
nevents = header(37); % number of external events
nslow = header(38);  % number of slow channels
npw = header(39);  % number of points in wave
npr = header(40);  % number of points before threshold
tscounts = fread(fid, [5, 130], 'int32');
wfcounts = fread(fid, [5, 130], 'int32');
evcounts = fread(fid, [1, 512], 'int32');

% next is 1020*ndsp bytes of PL_ChanHeaders

% read the data
idsp = 0;
while idsp < ndsp
    chanheader = fread(fid, 255, 'int32');      % 1020 bytes
    idsp = idsp + 1;
    % Name, Signame take up 16 ints, then gain is 5th int after that, so its the
    % 21st int
    gains(idsp) = chanheader(21)*1000;
   
    if feof(fid) == 1
       break
    end   
end
disp(strcat('number of gains returned = ', num2str(idsp)));

fclose(fid);