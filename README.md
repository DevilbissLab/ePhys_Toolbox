# ePhys_Toolbox
This is my repository for all Matlab code written for our analyses


Data Struct
.Version							(Generally the imported File Version)
.SubjectID
.Comment
.StartDate
.FileFormat
.nSeconds
.nChannels
.FileName
.Channel
	.Name
	.ChNumber
	.Units
	.nSamples
	.Hz
	.Data
	.Labels (Added by SleepScoring)
	.Type (FIFF - optional)
	.Tag (FIFF - optional)
	.Number (FIFF,DSI - optional)<<<This may be ChNumber
	.MatrixLoc (DSI - optional)
	.FullScale (DSI - optional)
	.ts (DSI - optional)
	.Transducer (EDF - optional)
	.PhysMin (EDF - optional)
	.PhysMax (EDF - optional)
	.DigMin (EDF - optional)
	.DigMax (EDF - optional)
	.PreFilter (EDF - optional)
	.RecordnSamples (EDF - optional)
	.ADFrequency (NEX - optional) (ver 1.6 changed to .Hz for compatibility)
	.timestamps (NEX - optional) (ver 1.6 Merge with .ts)
	.fragmentStarts (NEX - optional)
	.type (NEX - optional)
	.varVersion (NEX - optional)
	.FilePosDataOffset (NEX - optional)
	.nEvents (NEX - optional)
	.WireNumber (NEX - optional)
	.UnitNumber (NEX - optional)
	.Gain (NEX - optional)
	.Filter (NEX - optional)
	.XPos (NEX - optional)
	.YPos (NEX - optional)
	.WFrequency (NEX - optional)
	.ADtoMV (NEX - optional)
	.NPointsWave (NEX - optional)
	.NMarkers (NEX - optional)
	.MarkerLength (NEX - optional)
	.MVOfffset (NEX - optional)
.neurons (NEX - optional)
.events (NEX - optional)
.intervals (NEX - optional)
.waves (NEX - optional)
.popvectors (NEX - optional)
.markers (NEX - optional)
.VersionName (DSI - optional)
.SubjectUID (FIFF - optional)
.BirthDate (FIFF - optional)
.Gender (FIFF - optional)
.Handed (FIFF - optional)
.Weight (FIFF - optional)
.Height (FIFF - optional)
.HospID (FIFF - optional)
.SubjectName (FIFF - optional)
.Hz (FIFF,PLX - optional)
.Coord3D (FIFF - optional)
.FirstSample (FIFF - optional)
.freq (NEX - optional) (ver 1.6 changed to .Hz for compatibility)
.nRecords (FIFF,EDF - optional)

.Trodalness
.NPW
.PrethresholdTime
.SpikePeak
.SpikeADResBits
.SlowPeakV
.SlowADResBits, plx.Duration, plx.DateTime

