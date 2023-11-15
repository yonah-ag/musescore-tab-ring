/* MuseScore Plugin: Tab Ring
 *
 * Copyright © 2023 yonah_ag, scorster
 *
 *  This program is free software; you can redistribute it or modify it under
 *  the terms of the GNU General Public License version 3 as published by the
 *  Free Software Foundation and appearing in the accompanying LICENSE file.
 *
 *  Description
 *  -----------
 *  Automated "Let Ring" for solo TAB scores
 *
 */

import QtQuick 2.2
import QtQuick.Controls 1.5
import QtQuick.Layouts 1.3
import QtQuick.Controls.Styles 1.4
import QtQuick.Dialogs 1.2
import Qt.labs.settings 1.0
import MuseScore 3.0

MuseScore
{
   version: "1.0.0"
   description: "Automated 'Let Ring' for tablature staves"
   menuPath: "Plugins.TAB Ring"
   requiresScore: true
   pluginType: "dialog"

// Parameters

   property var isTab : 0 // 0:No, 1:TAB Only, 2:Tab + Notation
   property var maxRing : 0 // max ring, calculated from UI
   property var pickGap : 0 // gap due to picking
   property var dolMez : 0 // default $ option for measures
   property var dolHar : 0 // default $ option for harmony (chord) symbols
   property var zPlay : false // Score is in playback mode
   property var iTick : 0 // bookmarked playback tick

   property var zDis  : false // stop dissonant 2nds
   property var zThru : true  // ring through rests in same voice
   property var zArt : true  // keep articulations
   property var zLog  : false // view processing log
   property var zFace : false // reset face value, (1000‰)
   property var zDel  : false // delete play events
   property var okMax : true  // is maximum ring input ok?
   property var okGap : true  // is picking gap input ok?
   property var disStop : 0

   property var rTok: ["A","O","S","F","N"]
   property var bitStop: [0, 8, 16, 32, 64, 128, 256, 512, 1024, 2048] // $ string stop bits for up to 9 strings (values 1-7 for other $control codes)

// Global variables

   property var nofSel : 0 // count of selected elements
   property var nofUpd : 0 // count of notes updated
   property var tout : "" // text output file
   property var tlog : "" // text output log line
   property var tdet : "" // message dialog detail
   property var nofM : 0 // no. of measures in score
   property var nofS : 0 // no. of segments in score
   property var nofN : 0 // no. of notes in score
   property var tickEnd : 0 // end of score tick
   property var tickFr : 0 // Tick From
   property var tickTo : 0 // Tick To
   property var ringLim : 0 // Ring limit imposed by Musescore plugin API

// Score Map

   property var mIX : [] // Map index
   property var mMez : []
   property var mTick : []
   property var mStr : []
   property var mFret : []
   property var mFace : [] // Face value length
   property var mMIDI : [] // MIDI note value for 2nds detection
   property var mTup : [] // Tuplet factor or 0:Not a tuplet
   property var mTie : [] // 0:No tie, 1:Tie forward, -1:Tie back
   property var mVox : [] // Voice 0-3 within each Part
   property var mPlay : [] // Play flag: <P>=Play, <X>=Silent
   property var mOnT : [] // Ontime‰
   property var mLen : [] // Length‰
   property var mOnTk : [] // Ontime in ticks
   property var mLnTk : [] // Length in ticks
   property var mDoll : [] // $ string codes
   property var mArt : [] // Articulations


   onRun: { checkTAB(); }
   
//=================================================================================================================================

   function ringNote(ix,note,noto) // current note index and object
   {
      var noteTick = mTick[ix]; // current note tick
      var noteStrg = mStr[ix]; // current note string
      var noteFret = mFret[ix]; // current note fret
      var noteMIDI = mMIDI[ix]; // current note MIDI pitch number
      var noteFval = mFace[ix]; // note length (face value) in ticks
      var noteVox = mVox[ix];   // voice - used when not ringing thru rests
      var noteTied = false; // Tie forward status of note
      var notePlay = mPlay[ix];
      var maxTick = 0;
      var nextTick = 0; // tick of next note
      var noteRing = 0; // note ring in ticks
      var noteLen = 0; // note ring length in 1/1000 ths of face value
      var tupFx = mTup[ix]; // tuplet factor of current note
      var onTk = mOnTk[ix]; // ontime of current note (in ticks)
      var nextOnTk = 0; // ontime of next note (in ticks)
      var dollTick = 0;  // used with "$" string stop
      var dollType = 0;
      var zDoll = false; // the note was stopped by a Ring Token
      var disFret = 0; // dissonant fret span

      if (zLog) tlog = "<tr><td>" + ix + "<td><td>" + noteTick + "<td>" + onTk + "<td>" + noteFval
      + "<td>" + noteStrg + "." + mFret[ix] + "<td>" + mDoll[ix];

      if (zFace) {
         if (zDel) {
            note.playEvents = [];
            if (isTab == 2) noto.playEvents = [];
         }
         else {
            note.playEvents[0].len = 1000 - note.playEvents[0].ontime;
            if (isTab == 2)
               if (noto) noto.playEvents[0].len = 1000 - noto.playEvents[0].ontime;
            nofUpd++;
         }
      }
      else if (notePlay == "P" && mTie[ix] >= 0) {
         if (noteFval >= maxRing) { // if current note length >= max
            noteRing = maxRing;
            if (zLog) tlog += "<td>max";
         }
         else {
            if (zLog) tlog += "<td>next";
            maxTick = noteTick + maxRing; // Tick of current note + max
            while (noteRing == 0) {
               ++ix;
               nextTick = mTick[ix];
               while (nextTick == noteTick) { // notes in same chord
                  ++ix;
                  nextTick = mTick[ix]
               }
               if (nextTick == tickEnd) {
                  nextOnTk = 0;
                  if (zLog) tlog += "<tr><td><td>" + ix + "<td>" + nextTick
                  + "<td><td><td><td><td>eos";
               }
               else {
                  nextOnTk = mOnTk[ix];
                  if (zLog) tlog += "<tr><td>&nbsp;<td>" + ix + "<td>" + nextTick
                  + "<td><td><td>"+mStr[ix]+"."+mFret[ix]+"<td>"+mDoll[ix];
               }

               if (nextTick >= maxTick) { // if next tick at or beyond limit
                  if (zLog) tlog += "<td>limit";
                  if (noteTied)
                     noteRing = nextTick - noteTick;
                  else
                     noteRing = maxRing;
               }
               else if (mDoll[ix] > 0) { // if $ Ring Token
                  dollType = mDoll[ix];
                  switch (dollType) {
                  case 1: // $NONE
                     zDoll = true;
                     noteRing = nextTick - noteTick;
                     if (zLog) tlog += "<td>$"+dollType;
                     break;
                  case 2: // $OPEN
                     if (noteFret > 0) {
                        zDoll = true;
                        noteRing = nextTick - noteTick;
                        if (zLog) tlog += "<td>$"+dollType;
                     }
                     break;
                  case 3: // $SAME
                     if (noteFret > 0) {
                        dollTick = nextTick;
                     }
                     break;
                  case 4: // $FRET
                     if (noteFret == 0) {
                        zDoll = true;
                        noteRing = nextTick - noteTick;
                        if (zLog) tlog += "<td>$"+dollType;
                     }
                     else {
                        dollTick = nextTick;
                     }
                     break;
                  default:
                     if ((bitStop[noteStrg] & mDoll[ix]) > 0) {
                        zDoll = true;
                        noteRing = nextTick - noteTick;
                        if (zLog) tlog += "<td>$"+dollType;
                        break;
                     }
                  }
               }
               if (noteRing == 0) {
                  if (nextTick >= tickEnd) { // If End-of-Score
                     noteRing = tickEnd - noteTick;
                  }
                  else if (mStr[ix] == noteStrg) { // if next note on same string
                     if (mTie[ix] < 0 ) { // if next note has tie back
                        if (zLog) tlog += "<td>tieBack<td>" + mFace[ix];
                        noteFval += mFace[ix] ; // extend current note by tie length
                        noteTied = true;
                     }
                     else {
                        if (dollTick > 0) { // $
                           if (noteFret != mFret[ix]) {
                              if (zLog) tlog += "<td>$"+dollType;
                              nextTick = dollTick;
                              dollTick = 0;
                           }
                        }
                        else {
                           if (zLog) tlog += "<td>string";
                        }
                        noteRing = nextTick - noteTick - pickGap;
                        if (noteRing < pickGap) noteRing = pickGap;
                     }
                  }
                  else if (mStr[ix] == 0) { // Rest
                     if (!zThru) {
                        if (noteVox == mVox[ix]) {
                           noteRing = nextTick - noteTick;
                           if (zLog) tlog += "<td>rest";
                        }
                     }
                  }
                  else if (zDis) {
                     disFret = Math.abs(noteMIDI-mMIDI[ix]);
                     if (disFret == 1 || disFret == 2) {
                        if(noteStrg>=disStop || mStr[ix]>=disStop) {
                           noteRing = nextTick - noteTick;
                           if (zLog) tlog += "<td>2nd";
                        }
                     }
                  }
                  else if (ix>nofN) {
                    if (zLog) tlog += "<td>exit!";
                    noteRing = -1;
                  }
               }
            }
         }
         if (zLog) tlog += "<td>" + noteRing;
         if (noteRing > 0) {
            if (zDoll)
               noteLen = Math.min(Math.floor(1000 * (noteRing) / noteFval), ringLim);
            else
               noteLen = Math.min(Math.floor(1000 * (noteRing + nextOnTk) / noteFval), ringLim);
            if (tupFx) noteLen = Math.floor(1000 + tupFx * (noteLen - 1000));
            if (onTk != 0) noteLen -= Math.floor(1000 * onTk / noteFval);
            if (zLog) tlog += "<td>R" + noteLen;
            if (noteLen < 125) noteLen = 125; // don't let notes get too small
            note.playEvents[0].len = noteLen;
            if (isTab == 2)
               if (noto) noto.playEvents[0].len = noteLen; // sync linked stave (if it exists)
            nofUpd++;
         }
      }
      else if (note.tieBack != null)
         if (zLog) tlog += "<td>tied";
      else {
         if (notePlay == "X") {
            noteLen = Math.floor(48000/noteFval);
            if (zLog) tlog += "<td>nonp<td>" + noteLen;
            note.playEvents[0].len = noteLen; // shorten non-playing "stop note" for PRE view
            if (isTab == 2)
               if (noto) noto.playEvents[0].len = noteLen; // sync linked stave
            nofUpd++;
         }
         else
            if (zLog) tlog += "<td>artic<td>";
      }
      if (zLog) tout += tlog;
   }

//=================================================================================================================================

   function letRing() // Apply Let Ring to score or selection
   {   
      var seg;
      var elm; var note;  // Controlling element and note
      var elmo; var noto; // Other element and note (synced TAB and notation)
      var nix = 0; // note map index
      var mez = curScore.firstMeasure;

      nofUpd = 0;
      if (mscoreVersion == 30602)
         ringLim = 2000;  // MS3.6.2
      else
         ringLim = 60000; // MS3.7.X
            
      if (zLog) {
         tout += "<h2>Tab Ring</h2>";
         tout += "<p>From: " + tickFr + ", To: " + tickTo + ", maxRing: " + maxRing + " ticks";
         tout += "<p><table border=1 cellspacing=2 cellpadding=4><tr><td> IX<td> IY";
         tout += "<td>Tick<td>OnTix<td>Lent<td>Str.Fr<td>$SC<td>Action<td>Ring<td>Len‰</tr>";
      }

      curScore.startCmd();

      while (mez) {
         seg = mez.firstSegment;
         while (seg) {
            if (seg.segmentType == 512) { // chordrest
               for (var tt = 0; tt < 4; ++tt) { // First 4 tracks of score only
                  elm = seg.elementAt(tt);
                  if (elm) {
                     if (elm.type == 93) { // chord
                        if (isTab == 2) elmo = seg.elementAt(tt+4); // synced track
                        for (var nn in elm.notes) {
                           note = elm.notes[nn];
                           if (seg.tick >= tickFr && seg.tick < tickTo) {
                              if (zFace) elm.playEventType = 0; 
                              if (isTab == 2) noto = elmo.notes[nn]
                              ringNote(nix,note,noto);
                           }
                           ++nix;
                        }
                     }
                     else if (elm.type == 25) // rest
                       ++nix;
                  }
               }
            }
            seg = seg.nextInMeasure;
         }
         mez = mez.nextMeasure;
      }
      curScore.endCmd();

      if (zLog) tout += "</table></p><h1>&nbsp;</h1>";
   }
 
//=================================================================================================================================

   function mapScore() // Build score map variables
   {
      var el; var elm; var elm0; var elm1
      tickFr = 0; tickTo = tickEnd; nofSel = 0;// initialise to no selection

      nofSel = curScore.selection.elements.length;
      if (nofSel > 0) {
         if (zArt) { // Keep articulations
            for (el in curScore.selection.elements) {
               elm = curScore.selection.elements[el];
               if (elm.type == 29) {
                  mArt.push(elm.parent.parent.tick);
               }
            }
         }
         if (curScore.selection.isRange) {
            tickFr = curScore.selection.startSegment.tick;
            if (curScore.selection.endSegment)
               tickTo = curScore.selection.endSegment.tick;
               if (tickTo == 0) tickTo = tickEnd; // beyond last seg of score
         }
         else { // List type selection rather than range
            elm0 = curScore.selection.elements[0];
            elm1 = curScore.selection.elements[nofSel-1];
            if (elm0.type == 20 && elm1.type == 20) {
               tickFr = elm0.parent.parent.tick;
               tickTo = elm1.parent.parent.tick+1;
            }
         }
      }
      else if (zArt) { // build mArt when there's no selection
         cmd('select-all');
         for (el in curScore.selection.elements) {
            elm = curScore.selection.elements[el];
            if (elm.type == 29) {
               mArt.push(elm.parent.parent.tick);
            }
         }
         curScore.selection.clear();
      }
      tout = ""; tlog = ""; nofM = 0; nofS = 0; nofN = 0;

      var seg; var elm; var note;
      var tick;
      var fval; // face value length in ticks 
      var lent; // actual length in ticks
      var tupl; // tuplet factor
      var onti; // ontime
      var mez = curScore.firstMeasure;
      var nix = 0; var tt = 0; var ii = 0;
      var anno; // annotation
      var doll = 0; // dollar code
      var dolt = ""; // dollar text
      var dolc = ""; // dollar code
      var doln; // dollar string number

      var mez = curScore.firstMeasure;
      while (mez) {
         ++nofM;
         seg = mez.firstSegment;
         while (seg) {
            if (seg.segmentType == 512) { // chordrest
               ++nofS;
               tick = seg.tick;
               if (seg.annotations.length > 0) {
                  for (var aa in seg.annotations) {
                     anno = seg.annotations[aa];
                     if (anno.type == 47 || anno.type == 48) { // harmony or fretboard diagram
                        doll = dolHar;
                     }
                     else if (anno.type == 42 && (anno.text.charAt(0) == "$" || anno.text.charAt(0) == "®")) { 
                        dolt = anno.text;
                        dolc = dolt.charAt(1).toUpperCase();
                        if (dolc=="N") { // Ring NONE
                           doll=1;
                           break;
                        }
                        else if (dolc=="O") { // Ring OPEN only
                           doll=2;
                           break;
                        }
                        else if (dolc=="S") { // Ring SAME fret inc. open
                           doll=3;
                           break;
                        }
                        else if (dolc=="F") { // Ring Same FRET exc. open
                           doll=4;
                           break;
                        }
                        else if (dolc=="A") { // Ring ALL strings
                           doll=0;
                           break;
                        }
                        else { // Mute listed strings
                           doll = 0; // sum of bit flags
                           for (ii = 1; ii < dolt.length; ++ii) {
                              doln = parseInt(dolt.charAt(ii));
                              if (isNaN(doln))  // non-numeric ends dolt processing
                                 break;
                              else {
                                 doll += bitStop[doln]; // bit flag for string 1-9
                              }
                           }
                        }
                     }
                  }
               }
               for (tt = 0; tt < 4; ++tt) { // only first 4 tracks in stave
                  elm = seg.elementAt(tt);
                  if (elm) {
                     if (elm.type == 93) { // chord
                        fval = elm.duration.ticks;
                        if (elm.tuplet == null)
                           tupl = 0;
                        else {
                           tupl = (elm.tuplet.actualNotes / elm.tuplet.normalNotes).toFixed(3);
                           fval = Math.floor(fval / tupl);
                        }
                        for (var nn in elm.notes) {
                           note = elm.notes[nn];
                           mIX.push(nofN);
                           mMez.push(nofM);
                           mTick.push(tick);
                           mStr.push(1+note.string);
                           mFret.push(note.fret);
                           mMIDI.push(note.pitch);
                           mFace.push(fval);
                           mTup.push(tupl);
                           if (note.tieForward != null)
                              mTie.push(1);
                           else if ( note.tieBack != null)
                              mTie.push(-1);
                           else
                              mTie.push(0);
                           mVox.push(tt+1);
                           if (note.play) {
                              if (zArt) {
                                 if (mArt.indexOf(tick) >= 0)
                                    mPlay.push("A");
                                 else
                                    mPlay.push("P");
                              }
                              else
                                 mPlay.push("P");
                           }
                           else {
                              mPlay.push("X");
                           }
                           onti = note.playEvents[0].ontime; // OnTime‰
                           lent = note.playEvents[0].len; // Len‰
                           mOnT.push(onti);
                           mOnTk.push(Math.floor(fval * onti / 1000));
                           mLen.push(lent);
                           mLnTk.push(Math.floor(fval * lent / 1000));
                           mDoll.push(doll);
                           ++nofN;
                        }
                     }
                     else if (elm.type == 25) { // rest
                        mIX.push(nofN);
                        mMez.push(nofM);
                        mTick.push(tick);
                        mStr.push(0);
                        mFret.push(0);
                        mMIDI.push(0);
                        mFace.push(elm.duration.ticks);
                        mTup.push(0);
                        mTie.push(0);
                        mVox.push(tt+1);
                        mPlay.push("R");
                        mOnT.push(0);
                        mOnTk.push(0);
                        mLen.push(0);
                        mLnTk.push(0);
                        mDoll.push(0);
                        ++nofN;
                     }
                  }
               }
               doll = 0;
            }
            seg = seg.nextInMeasure;
         }
         mez = mez.nextMeasure;
         doll = dolMez; // default doll for next measure
      }
      mIX.push(nofN); // end of score
      mMez.push(0);
      mTick.push(tickEnd);
      mStr.push(0);
      mFret.push(0);
      mDoll.push(0);
      if (zLog) {
         tout += "<h2>Score Map</h2>";
         tout += "<p><table border=1 cellspacing=2 cellpadding=4>";
         tout += "<tr><td>IX<td>Mez<td>Tick<td>Str.Fr<td>Fval,Tup<td>Tie";
         tout += "<td>Vox<td>MIDI<td>Play<td>On,Ln‰<td>OnT,LenT<tk><td>RTok</tr>";
         for (ii=0; ii < nofN; ++ii) {
            tick = mTick[ii];
            if (tick >= tickFr && tick < tickTo) {
               tout += "<tr><td>" + mIX[ii] + "<td>&nbsp;" + mMez[ii] + "<td>" + tick;
               if (mStr[ii]>0)
                  tout += "<td>&nbsp;" + mStr[ii] + "." + mFret[ii]; // note
               else
                  tout += "<td>R"; // rest
               tout += "<td>" + mFace[ii] + ", " + mTup[ii] + "<td>&nbsp;" + mTie[ii] + "<td>V" + mVox[ii];
               tout += "<td>&nbsp;" + mMIDI[ii] + "<td>&nbsp; " + mPlay[ii] + "<td>" + mOnT[ii] + ", " + mLen[ii];
               tout += "<td>" + mOnTk[ii] + ", " + mLnTk[ii] + "<td>&nbsp;" + mDoll[ii] + "</tr>";
            }
         }
         tout += "<tr><td>" + nofN + "<td>0<td>" + tickEnd + "<td>eos</tr></table></p><h2>&nbsp;</h2>";
      }
   }

//=================================================================================================================================

   function visTokens(visi)
   {
      var seg; var mez; var anno;
      tdet = "TAB Ring " + version;
      checkTAB();
      if (isTab > 0) {
         curScore.startCmd();
         mez = curScore.firstMeasure;
         while (mez) {
            seg = mez.firstSegment;
            while (seg) {
               if (seg.segmentType == 512) { // chordrest
                  if (seg.annotations.length > 0) {
                     for (var aa in seg.annotations) {
                        anno = seg.annotations[aa];
                        if (anno.type == 42 && (anno.text.charAt(0) == "$" || anno.text.charAt(0) == "^")) {
                           anno.visible = visi;
                        }
                     }
                  }
               }
               seg = seg.nextInMeasure;
            }
            mez = mez.nextMeasure;
         }
         curScore.endCmd();
         if (visi)
            tdet = tdet + "\nTokens visible.";
         else
            tdet = tdet + "\nTokens hidden.";

         runInfo.text = tdet;
      }
   }

//=================================================================================================================================

   function addToken(oTok)
   {
      var tokn; var addT;
      var cur = curScore.newCursor();
      if (curScore.selection.elements.length == 1) {
         if (curScore.selection.elements[0].type == 20) {  // note
            if (oTok >= 0) 
               tokn = rTok[oTok];
            else
               tokn = sTok.text;

            cur.inputStateMode=Cursor.INPUT_STATE_SYNC_WITH_SCORE;
            addT = newElement(Element.STAFF_TEXT);
            addT.text = tokPrefix.text + tokn;
            addT.placement = Placement.ABOVE;
            addT.align = 0;
            addT.autoplace = true;
            curScore.startCmd();
            cur.add(addT);
            curScore.endCmd()
         }
      }
   }

//=================================================================================================================================

   function showDocu()
   {
      runInfo.text = "Opening documentation";
      Qt.openUrlExternally("https://sites.google.com/view/tab-ring");
   }

//=================================================================================================================================

   function checkTAB()
   {
      if (curScore.parts[0].hasTabStaff) { // Check that first part has TAB
         if (curScore.parts[0].hasPitchedStaff) isTab = 2; else isTab = 1;
      }
      else {
         isTab = 0;
         tdet = "Tablature is required in the first part.";
         tdet += "\nSee TAB Ring User Guide for details.";
         runInfo.text = tdet;
         infoStop.visible = true;
         btnClrInfo.visible = true;
      }
   }

//=================================================================================================================================

   function runMain(reset)
   {
      infoStop.visible = false;
      runInfo.text = "TAB Ring " + version;
      checkTAB();
      if (isTab > 0) {
         zDis = chkDis2nds.checked;
         zThru = chkRingThru.checked;
         zLog = chkVuLog.checked;
         zFace = reset;
         zArt = chkArtic.checked;
      
         tickEnd = curScore.lastSegment.tick;
         
         if (reset) {
            dolMez = 0;
            dolHar = 0;
         }
         else {
            dolHar = inpChordStop.currentIndex;
            dolMez = inpMeasuStop.currentIndex;
            disStop = 6-inpDis2nds.currentIndex;
         }

         maxRing = inpMaxRQ.value;
         if (maxRing == 0) maxRing = 240; else maxRing = 480 * maxRing;
         pickGap = inpPickGap.value;
         if (pickGap > 0) pickGap = 18 + 6 * pickGap;
         if (zLog) tout = "<html><body>";

         mapScore();
         letRing();
         cmd("play");
         cmd("play");

         tdet = "TAB Ring " + version;
         tdet += "\nMeasures: " + nofM;
         tdet += "  |  Notes: " + nofN;

         if (zLog) {
            tout += "</body></html>";
            popInfo.text = tout;
            tout = "";
            infoWin.visible = true;
         }
         if (zFace)
            if (zDel) {
               inpMaxRQ.value = 4;
               tdet = "Play events have been deleted.";
               tdet += "\nSave score then re-open to complete the process.";
               btnDelPE.visible = false;
               btnSymShow.visible = false;
               btnSymHide.visible = false;
               infoStop.visible = true;
               uiRow9.visible = false;
               toolHdr.visible = false;
               toolBtn.visible = false;
            }
            else
               tdet += "  |  Reset: " + nofUpd;
         else
            tdet += "  |  Updated: " + nofUpd;

         runInfo.text = tdet;
      
 // Clear Maps
 
         mIX.length = 0;
         mMez.length = 0;
         mTick.length = 0;
         mStr.length = 0;
         mFret.length = 0;
         mFace.length = 0;
         mMIDI.length = 0;
         mTup.length = 0;
         mTie.length = 0;
         mVox.length = 0;
         mPlay.length = 0;
         mOnT.length = 0;
         mLen.length = 0;
         mOnTk.length = 0;
         mLnTk.length = 0;
         mDoll.length = 0;
         mArt.length = 0;
      }
   }

//=================================================================================================================================


// USER INTERFACE

   id: uiTabRing
   width: 370
   height: 430

   RowLayout { id: uiRow1
      x: 15; y:15
      Label { id: lblRingA
         Layout.preferredWidth: 100
         color: "#000000"
         text: "Maximum Ring"
      }
      SpinBox { id: inpMaxRQ
         decimals: 0
         minimumValue: 0
         maximumValue: 9
         value: 4
         Layout.leftMargin: 15
         Layout.preferredWidth: 40
         Layout.preferredHeight: 24
      }
      Label { id: lblRingB
         color: "#000000"
         Layout.leftMargin: 20
         Layout.preferredWidth: 100
         Text {
            color: "#404040"
            text: "0 - 9   ( quarter notes )"
         }
      }
   }
   RowLayout { id: uiRow2 // Picking Gap
      x:15; y: uiRow1.y+27
      Label { id: lblGapA
         Layout.preferredWidth: 100
         color: "#000000"
         text: "Picking Gap"
      }
      SpinBox {
         id: inpPickGap
         decimals: 0
         minimumValue: 0
         maximumValue: 7
         value: 2
         Layout.leftMargin: 15
         Layout.preferredWidth: 40
         Layout.preferredHeight: 24
      }
      Label { id: lblGapB
         color: "#000000"
         Layout.leftMargin: 20
         Layout.preferredWidth: 100
         Text {
            color: "#404040"
            text: "0 - 7   ( 1/256th notes )"
         }
      }
   }
   RowLayout { id: uiRow3
      x: 15; y: uiRow2.y+29
      Label { id: lblChordStop
         Layout.preferredWidth: 100
         color: "#000000"
         text: "At chord symbols"
      }
      ComboBox {
         id: inpChordStop
         model: ["No extra processing", "Stop all strings", "Ring open strings only",
                 "Ring open strings and same fret", "Ring same fret only"]
         Layout.leftMargin: 15
         Layout.preferredWidth: 219
         currentIndex: 0
      }
   }
   RowLayout { id: uiRow4
      x: 15; y: uiRow3.y+30
      Label { id: lblMeasuStop
         Layout.preferredWidth: 100
         color: "#000000"
         text: "At bar lines"
      }
      ComboBox {
         id: inpMeasuStop
         model: ["No extra processing", "Stop all strings", "Ring open strings only",
                 "Ring open strings and same fret", "Ring same fret only"]
         Layout.leftMargin: 15
         Layout.preferredWidth: 219
         currentIndex: 0
      }
   }

   Rectangle { id: uiRow5
      x: 30; y: uiRow4.y+35
      width: 100; height: 22; color: "transparent"
      MouseArea {
         anchors.fill: parent
         onClicked: { chkRingThru.checked = !chkRingThru.checked }
      }
   }
   Rectangle { id: uiRow5a
      x: 205; y: uiRow5.y
      width: 100; height: 22; color: "transparent"
      MouseArea {
         anchors.fill: parent
         onClicked: { chkArtic.checked = !chkArtic.checked }
      }
   }
   RowLayout { id: uiRow5b
      x: 15; y: uiRow5.y
      CheckBox { id: chkRingThru;
         Layout.preferredWidth: 15
         checked: true
         text: ""
      }
      Label { id: lblRingThru
         Layout.preferredWidth: 120
         color: "#000000"
         text: "Ring through rests"
      }
      CheckBox { id: chkArtic;
         Layout.leftMargin: 75
         Layout.preferredWidth: 15
         checked: true
         text: ""
      }
      Label { id: lblArtic
         Layout.preferredWidth: 80
         color: "#000000"
         text: "Keep articulations"
      }
   }
   Rectangle { id: uiRow6
      x: 30; y: uiRow5.y+25
      width: 100; height: 22; color: "transparent"
      MouseArea {
         anchors.fill: parent
         onClicked: { chkDis2nds.checked = !chkDis2nds.checked }
      }
   }
   Rectangle { id: uiRow6a
      x: 205; y: uiRow6.y
      width: 100; height: 22; color: "transparent"
      MouseArea {
         anchors.fill: parent
         onClicked: { chkVuLog.checked = !chkVuLog.checked }
      }
   }
   RowLayout { id: uiRow6b
      x: 15; y: uiRow6.y
      CheckBox { id: chkDis2nds;
         Layout.preferredWidth: 15
         checked: false
         text: ""
      }
      Label { id: lblDis2nds
         Layout.preferredWidth: 60
         color: "#000000"
         text: "Stop 2nds"
      }
      ComboBox {
         id: inpDis2nds
         model: ["6-5", "6-5-4", "6-5-4-3","6-5-4-3-2", "6-5-4-3-2-1"]
         Layout.leftMargin: 0
         Layout.preferredWidth: 110
         currentIndex: 0
      }
      CheckBox { id: chkVuLog;
         Layout.leftMargin: 20
         Layout.preferredWidth: 15
         checked: false
         text: ""
      }
      Label { id: lblVuLog
         Layout.preferredWidth: 80
         color: "#000000"
         text: "View process log"
      }
   }
   RowLayout { id: uiRow7
      x: 15; y: uiRow6.y+40
      Button { id: btnDelPE
         Layout.preferredWidth: 110
         Layout.preferredHeight: 22
         text: "Reset Playback"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#f0f0f0"
               radius: 11
            }
         }
         tooltip: "Requires score reload"
         onClicked: { zDel = true; runMain(true)}
      }
      Button { id: btnSymHide
         Layout.preferredWidth: 110
         Layout.preferredHeight: 22
         text: "Hide Tokens"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#f0f0f0"
               radius: 11
            }
         }
         onClicked: visTokens(false);
      }
      Button { id: btnSymShow
         Layout.preferredWidth: 110
         Layout.preferredHeight: 22
         text: "Show Tokens"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#f0f0f0"
               radius: 11
            }
         }
         onClicked: visTokens(true);
      }
   }
   RowLayout { id: uiRow8
      x:15; y: uiRow7.y+28; visible: true
      Button { id: btnDocu
         Layout.preferredWidth: 340
         Layout.preferredHeight: 30
         text: "TAB Ring User Guide"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#f0f0f0"
               radius: 15
            }
         }
         onClicked: showDocu();
      }
   }
   RowLayout { id: uiRow9
      x:15; y: uiRow8.y+36
      Button { id: btnReset
         Layout.preferredWidth: 168
         Layout.preferredHeight: 30
         tooltip: "Reset note ring to face value in full score or selected range"
         text: "Reset Ring"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#c9dbe8"
               radius: 15
            }
         }
         onClicked: runMain(true);
      }
      Button { id: btnApply
         Layout.preferredWidth: 167
         Layout.preferredHeight: 30
         text: "Apply Ring"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#d1e0d1"
               radius: 15
            }
         }
         tooltip: "Apply TAB Ring settings to full score or selected range"
         visible: true
         onClicked: runMain(false);
      }
   }
   Rectangle { id: infoStop
      x: 15; y: uiRow9.y;
      width: 340; height: 48;
      color: "#f8f8f8"; border.color:"#b0b0b0"; radius:3
      Label { id: lblinfoStop
         Layout.preferredWidth: 240
         x: 120; y:5
         font.pixelSize: 20; color: "#d00000"
         text: "IMPORTANT"
      }
      visible: false
   }
   TextArea { id: runInfo
      x: 15; y: uiRow9.y+45
      width: 340; height: 55
      textMargin: 10
      textFormat: TextEdit.PlainText
      readOnly: true
      wrapMode: TextEdit.Wrap
      text: "TAB Ring: " + version
   }
   RowLayout { id: toolHdr
      x:15; y: runInfo.y + 65
      visible: true
      Label { id: lblToolHdr
         Layout.preferredWidth: 100
         color: "#000000"
         text: "Ring Tokens"
      }
   }
   RowLayout { id: toolBtn
      x:15; y: toolHdr.y + 23
      visible: true

      Button { id: tokNone
         Layout.preferredWidth:48
         Layout.preferredHeight: 22
         text: "None"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#c9dbe8"
               radius: 10
            }
         }
         tooltip: "Ring no strings :: stop all strings"
         onClicked: { addToken(4) }
      }
      Button { id: tokAll
         Layout.preferredWidth:33
         Layout.preferredHeight: 22
         text: "All"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#d1e0d1"
               radius: 10
            }
         }
         tooltip: "Ring all strings"
         onClicked: { addToken(0) }
      }
      Button { id: tokOpen
         Layout.preferredWidth:48
         Layout.preferredHeight: 22
         text: "Open"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#d1e0d1"
               radius: 10
            }
         }
         tooltip: "Ring open strings only"
         onClicked: { addToken(1) }
      }
      Button { id: tokSame
         Layout.preferredWidth:48
         Layout.preferredHeight: 22
         text: "Same"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#d1e0d1"
               radius: 10
            }
         }
         tooltip: "Ring open and same fret strings"
         onClicked: { addToken(2) }
      }
      Button { id: tokFret
         Layout.preferredWidth:39
         Layout.preferredHeight: 22
         text: "Fret"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#d1e0d1"
               radius: 10
            }
         }
         tooltip: "Ring same fret strings (not open strings)"
         onClicked: { addToken(3) }
      }
      Button { id: tokStop
         Layout.preferredWidth:43
         Layout.preferredHeight: 22
         text: "Mute"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#d1e0d1"
               radius: 10
            }
         }
         tooltip: "Mute listed strings, e.g. $6"
         onClicked: { addToken(-1) }
      }
      TextField { id: sTok; // $stop_strings
         Layout.preferredWidth:29
         Layout.preferredHeight:22
         text: "6"
      }
      Button { id: tokPrefix
         Layout.preferredWidth:20
         Layout.preferredHeight:22
         text: "$"
         style: ButtonStyle {
            background: Rectangle {
               border.width: 1; border.color: "#999"; color: "#f0f0f0"
               radius: 10
            }
         }
         tooltip: "Toggle ring token symbol"
         onClicked: {
            if(tokPrefix.text == "$")
               tokPrefix.text = "®"
            else
               tokPrefix.text = "$"
         }
      }
   }
   ApplicationWindow {
      id: infoWin
      x: 20; y: 70
      width: 600; height: 800
      title: "TAB Ring Information"
      visible: false
      TextArea {
         id: popInfo
         width: infoWin.width; height: infoWin.height
         textMargin: 15
         textFormat: TextEdit.RichText
         readOnly: true
         wrapMode: TextEdit.Wrap 
         text: ""
      }
   }
   Settings {
      id: settings
      category: "PluginTabRing"
      property alias maxRing : inpMaxRQ.value
      property alias pickGap: inpPickGap.value
      property alias ringThru: chkRingThru.checked
      property alias dis2nds: chkDis2nds.checked
      property alias dis2str: inpDis2nds.currentIndex
      property alias keepArt: chkArtic.checked
      property alias chordStop: inpChordStop.currentIndex
      property alias measuStop: inpMeasuStop.currentIndex
      property alias tokChar: tokPrefix.text
   }
}