unit hxRecordViewerFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Grids, ActnList,
  ComCtrls, StdCtrls, ExtCtrls,
  MPHexEditor,
  hxGlobal, hxViewerItems, hxViewerGrids, hxGridViewerFrame;

type

  { TRecordViewerGrid }

  TRecordViewerGrid = class(TViewerGrid)
  private
    FFileName: String;
    FRecordStart: Integer;
    FRecordSize: Integer;
    function GetItem(ARow: Integer): TRecordDataItem;
    procedure SetItem(ARow: Integer; AItem: TRecordDataitem);
  protected
    procedure DefineColumns; override;
    function DistanceToZero(AOffset: Integer; IsForWideString: Boolean): Integer;
    procedure DoUpdateData; override;
    function SelectCell(ACol, ARow: Integer): Boolean; override;
    procedure UpdateSelection(ARow: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddItem(AItem: TRecordDataItem);
    procedure Advance(ADirection: Integer);
    procedure DeleteItem(ARow: Integer);
    procedure LoadRecordFromFile(const AFileName: String);
    procedure MoveItemDown;
    procedure MoveItemUp;
    procedure SaveRecordToFile(const AFileName: String);
    property FileName: String read FFileName;
    property RowItems[ARow: Integer]: TRecordDataItem read GetItem write SetItem;
  end;

  { TRecordViewerFrame }

  TRecordViewerFrame = class(TGridViewerFrame)
    acAdd: TAction;
    acEdit: TAction;
    acSaveAs: TAction;
    acDelete: TAction;
    acLoad: TAction;
    acMoveUp: TAction;
    acMoveDown: TAction;
    acSave: TAction;
    acPrevRecord: TAction;
    acNextRecord: TAction;
    ActionList: TActionList;
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    ToolBar: TToolBar;
    ToolButton1: TToolButton;
    ToolButton10: TToolButton;
    ToolButton11: TToolButton;
    ToolButton12: TToolButton;
    ToolButton13: TToolButton;
    ToolButton14: TToolButton;
    ToolButton2: TToolButton;
    ToolButton3: TToolButton;
    ToolButton4: TToolButton;
    ToolButton5: TToolButton;
    ToolButton6: TToolButton;
    ToolButton7: TToolButton;
    ToolButton8: TToolButton;
    ToolButton9: TToolButton;
    procedure acAddExecute(Sender: TObject);
    procedure acDeleteExecute(Sender: TObject);
    procedure acEditExecute(Sender: TObject);
    procedure acLoadExecute(Sender: TObject);
    procedure acMoveDownExecute(Sender: TObject);
    procedure acMoveUpExecute(Sender: TObject);
    procedure acNextRecordExecute(Sender: TObject);
    procedure acPrevRecordExecute(Sender: TObject);
    procedure acSaveAsExecute(Sender: TObject);
    procedure acSaveExecute(Sender: TObject);
    procedure ActionListUpdate(AAction: TBasicAction; var {%H-}Handled: Boolean);
  private
    FToolButtons: array of TToolButton;  // stores original order of toolbuttons
  protected
    function CreateViewerGrid: TViewerGrid; override;
    function GetDefaultColWidths(AIndex: Integer): Integer; override;
    function RecordViewerGrid: TRecordViewerGrid; inline;
    procedure RestoreToolButtons;
    procedure SetParent(AValue: TWinControl); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;


implementation

{$R *.lfm}

uses
  TypInfo, Math,
  hxHexEditor, hxRecordEditorForm;

{------------------------------------------------------------------------------}
{                           TRecordViewerGrid                                  }
{------------------------------------------------------------------------------}

constructor TRecordViewerGrid.Create(AOwner: TComponent);
begin
  FDataItemClass := TRecordDataItem;
  inherited Create(AOwner);
end;

destructor TRecordViewerGrid.Destroy;
begin
  if (HexEditor is THxHexEditor) then
  begin
    HexEditor.SelCount := 0;
    THxHexEditor(HexEditor).SecondSelStart := -1;
    THxHexEditor(HexEditor).SecondSelEnd := -1;
  end;
  inherited;
end;

procedure TRecordViewerGrid.AddItem(AItem: TRecordDataItem);
begin
  FDataList.Add(AItem);
  RowCount := RowCount + 1;
  UpdateData(HexEditor);
end;

procedure TRecordViewerGrid.Advance(ADirection: Integer);
var
  P : Integer;
begin
  P := HexEditor.GetCursorPos;
  inc(P, ADirection * FRecordSize);
  if (P < 0) or (P >= HexEditor.DataSize) then
    exit;
  HexEditor.SelStart := P;
  UpdateData(HexEditor);
  UpdateSelection(Row);
end;

{ Property indexes of TRecordDataItem:
  0=DataType, 1=DataSize, 2=Offset, 3=BigEndian, 4=Name }
procedure TRecordViewerGrid.DefineColumns;
var
  lCol: TGridColumn;
begin
  Columns.BeginUpdate;
  try
    Columns.Clear;

    lCol := Columns.Add;
    lCol.Tag := 4;  // TRecordItem property with index 4: Name
    lCol.Title.Caption := 'Name';
    lCol.Width := 120;
    lCol.SizePriority := 0;
    lCol.ReadOnly := true;

    lCol := Columns.Add;
    lCol.Tag := 0;  // inherited TDataItem property with index 0: DataType
    lCol.Title.Caption := 'Data type';
    lCol.Width := 80;
    lCol.SizePriority := 0;
    lCol.ReadOnly := true;

    lCol := Columns.Add;
    lCol.Tag := 1;  // inherited TDataItem property with index 1: Data size
    lCol.Title.Caption := 'Size';
    lCol.Alignment := taRightJustify;
    lCol.Width := 24;
    lCol.SizePriority := 0;
    lCol.ReadOnly := true;

    lCol := Columns.Add;
    lCol.Tag := -1;  // Value column
    lCol.Title.Caption := 'Value';
    lCol.Width := 100;
    lCol.SizePriority := 1;  // Expand column to fill rest of grid width
    lCol.ReadOnly := true;
  finally
    Columns.EndUpdate;
  end;
end;

procedure TRecordViewerGrid.DeleteItem(ARow: Integer);
begin
  FDataList.Delete(ARow - FixedRows);
  RowCount := RowCount - 1;
  UpdateData(HexEditor);
end;

function TRecordViewerGrid.DistanceToZero(AOffset: Integer; IsForWideString: Boolean): Integer;
const
  BUFSIZE = 1024;
var
  buf: array of byte;
  n: Integer;
  P: PChar;
  Pend: PChar;
  Pw: PWideChar;
  PwEnd: PWideChar;
begin
  Result := 0;
  repeat
    if AOffset + BUFSIZE < HexEditor.DataSize then
      n := BUFSIZE
    else
      n := HexEditor.DataSize - AOffset;
    SetLength(buf, n);
    HexEditor.ReadBuffer(buf[0], AOffset, n);
    if IsForWideString then begin
      Pw := PWideChar(@buf[0]);
      PwEnd := Pw + (n + 1) div 2;
      while Pw < PwEnd do
      begin
        if (Pw^ = #0) then
          exit;
        inc(Pw);
        inc(Result, 2);
      end;
    end else
    begin
      P := PChar(@buf[0]);
      PEnd := P + n + 1;
      while P < PEnd do
      begin
        if P^ = #0 then
          exit;
        inc(P);
        inc(Result);
      end;
    end;
    inc(AOffset, BUFSIZE);
  until (AOffset > HexEditor.DataSize);
end;

procedure TRecordViewerGrid.DoUpdateData;
var
  i: Integer;
  item: TDataItem;
  P: Integer;
  b: Byte = 0;
  w: Word = 0;
  n: Integer;
begin
  FRecordStart := HexEditor.GetCursorPos;
  P := FRecordStart;
  for i := 0 to FDataList.Count - 1 do
  begin
    item := FDataList[i] as FDataItemClass;
    item.Offset := P;
    n := item.DataSize;
    // negative DataSize means: Retrieve the datasize from the record itself.
    if (item.DataSize < 0) then
      case item.DataType of
        dtShortString:
          begin
            HexEditor.ReadBuffer(b, P, 1);
            n := b + 1;
          end;
        dtAnsiString:
          begin
            HexEditor.ReadBuffer(w, P, 2);
            if item.BigEndian then
              n := BEToN(w) + 2
            else
              n := LEToN(w) + 2;
          end;
        dtWideString:
          begin
            HexEditor.ReadBuffer(w, P, 2);
            if item.BigEndian then
              n := BEToN(w) * 2 + 2
            else
              n := LEToN(w) * 2 + 2;
          end;
        dtPChar:
          begin
            n := -(DistanceToZero(item.Offset, false) + 1);
          end;
        dtPWideChar:
          begin
            n := -(DistanceToZero(item.Offset, true) + 2) div 2;
          end;
      end;
    item.DataSize := n;
    inc(P, n);
  end;
  FRecordSize := P - FRecordStart;
  Invalidate;
end;

function TRecordViewerGrid.GetItem(ARow: Integer): TRecordDataItem;
begin
  Result := FDataList[ARow - FixedRows] as TRecordDataItem;
end;

procedure TRecordViewerGrid.LoadRecordFromFile(const AFileName: String);
var
  i, i0: Integer;
  L: TStringList;
  item: TRecordDataItem;
  sa: TStringArray;
  dt: TDataType;  // DataType
  ds: Integer;    // DataSize
  endian: Boolean;
  sep: String;
begin
  FDataList.Clear;

  FFileName := AFileName;

  L := TStringList.Create;
  try
    L.LoadFromFile(AFileName);
    if L.Count = 0 then
      raise EHexError.CreateFmt('Empty file "%s"', [AFileName]);

    i0 := 0;
    while (i0 < L.Count) and ((L[i0] = '') or (L[i0][1] = ';')) do
      inc(i0);

    if i0 >= L.Count then
      raise EHexError.CreateFmt('No contents in file "%s"', [AFileName]);

    if pos(DATA_FIELD_SEPARATOR, L[i0]) > 0 then
      sep := DATA_FIELD_SEPARATOR
    else if pos(',', L[i0]) > 0 then
      sep := ','
    else if pos(';', L[i0]) > 0 then
      sep := ';'
    else if pos(#9, L[i0]) > 0 then
      sep := #9
    else
      raise EHexError.CreateFmt('Unknown field separator in "%s"', [AfileName]);

    for i := i0 to L.Count - 1 do
    begin
      if L[i] = '' then
        Continue;

      sa := L[i].Split(sep);

      if Length(sa) < 3 then
        raise EHexError.Create('Invalid file structure, line "' +  L[i] + '".');

      if sa[2] = 'BE' then
        endian := true
      else if sa[2] = 'LE' then
        endian := false
      else
        raise EHexError.Create('Invalid file structure, line "' + L[i] + '".');

      dt := TDataType(GetEnumValue(TypeInfo(TDataType), sa[1]));
      if not InRange(ord(dt), ord(Low(TDataType)), ord(High(TDataType))) then
        raise EHexError.Create('Unknown data type, line "' + L[i] + '".');

      if dt in StringDatatypes then
        ds := StrToInt(sa[3])
      else
        ds := DataTypeSizes[dt];

      item := TRecordDataItem.Create(sa[0], dt, ds, endian);
      FDataList.Add(item);
    end;

  finally
    L.Free;
  end;
  RowCount := FDataList.Count + FixedRows;
  UpdateData(HexEditor);
end;

procedure TRecordViewerGrid.MoveItemDown;
begin
  if Row = RowCount - 1 then
    exit;
  FDataList.Exchange(Row - FixedRows, Row - FixedRows + 1);
  Row := Row + 1;
  UpdateData(HexEditor);
end;

procedure TRecordViewerGrid.MoveItemUp;
begin
  if Row = FixedRows then
    exit;
  FDataList.Exchange(Row - FixedRows, Row - FixedRows - 1);
  Row := Row - 1;
  UpdateData(HexEditor);
end;

procedure TRecordViewerGrid.SaveRecordToFile(const AFileName: String);
var
  i: integer;
  L: TStringList;
  Ls: TStringList;
  item: TRecordDataItem;
begin
  FFileName := AFileName;

  L := TStringList.Create;
  Ls := TStringList.Create;
  try
    Ls.Delimiter := DATA_FIELD_SEPARATOR;
    for i := 0 to FDataList.Count - 1 do
    begin
      item := FDataList[i] as TRecordDataItem;
      Ls.Clear;
      Ls.Add(item.Name);
      Ls.Add(GetEnumName(TypeInfo(TDataType), Integer(item.DataType)));
      Ls.Add(BigEndianStr[item.BigEndian]);
      if item.DataType in StringDataTypes then
        Ls.Add(IntToStr(item.DataSize));
      L.Add(Ls.DelimitedText);
    end;
    L.SaveToFile(AFileName);
  finally
    Ls.Free;
    L.Free;
  end;
end;

function TRecordViewerGrid.SelectCell(ACol, ARow: Integer): Boolean;
begin
  Result := inherited SelectCell(ACol, ARow);
  if Result and Assigned(HexEditor) and (HexEditor.DataSize > 0) then
  begin
    HexEditor.SelStart := HexEditor.GetCursorPos;
    UpdateData(HexEditor);
    UpdateSelection(ARow);
  end;
end;

procedure TRecordViewerGrid.SetItem(ARow: Integer; AItem: TRecordDataItem);
begin
  (FDataList[ARow - FixedRows] as TRecordDataItem).Assign(AItem);
  UpdateData(HexEditor);
end;

procedure TRecordViewerGrid.UpdateSelection(ARow: Integer);
var
  P: Integer;
  item: TDataItem;
begin
  P := FRecordStart + FRecordSize - 1;
  if P >= HexEditor.DataSize then
    exit;
  HexEditor.SelEnd := P;
  if (HexEditor is THxHexEditor) and (ARow >= FixedRows) then
  begin
    item := FDataList[ARow - FixedRows] as TDataItem;
    THxHexEditor(HexEditor).SecondSelStart := item.Offset;
    THxHexEditor(HexEditor).SecondSelEnd := item.Offset + abs(item.DataSize) - 1;
  end;
end;


{------------------------------------------------------------------------------}
{                            TRecordViewerFrame                                }
{------------------------------------------------------------------------------}

constructor TRecordViewerFrame.Create(AOwner: TComponent);
var
  i: Integer;
begin
  inherited Create(AOwner);
  SetLength(FToolButtons, Toolbar.ButtonCount);
  for i:=0 to Toolbar.ButtonCount-1 do
    FToolButtons[i] := Toolbar.Buttons[i];
end;

procedure TRecordViewerFrame.acAddExecute(Sender: TObject);
var
  item: TRecordDataItem = nil;
begin
  if RecordEditor('New record element', item) then
  begin
    RecordViewerGrid.AddItem(item);
  end;
end;

procedure TRecordViewerFrame.acDeleteExecute(Sender: TObject);
begin
  if MessageDlg('Do you really want to delete this record element?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then exit;

  RecordViewerGrid.DeleteItem(RecordViewerGrid.Row);
end;

procedure TRecordViewerFrame.acEditExecute(Sender: TObject);
var
  item: TRecordDataItem;
  r: Integer;
begin
  r := FGrid.Row;
  item := RecordViewerGrid.RowItems[r];
  if RecordEditor('Edit record element', item) then
  begin
    RecordViewerGrid.RowItems[r] := item;
  end;
end;

procedure TRecordViewerFrame.acLoadExecute(Sender: TObject);
begin
  with OpenDialog do
  begin
    InitialDir := ExtractFileDir(FileName);
    FileName := ExtractFileName(FileName);
    if Execute then
      RecordViewerGrid.LoadRecordFromFile(FileName);
  end;
end;

procedure TRecordViewerFrame.acMoveDownExecute(Sender: TObject);
begin
  RecordViewerGrid.MoveItemDown;
end;

procedure TRecordViewerFrame.acMoveUpExecute(Sender: TObject);
begin
  RecordViewerGrid.MoveItemUp;
end;

procedure TRecordViewerFrame.acNextRecordExecute(Sender: TObject);
begin
  RecordViewerGrid.Advance(+1);
end;

procedure TRecordViewerFrame.acPrevRecordExecute(Sender: TObject);
begin
  RecordViewerGrid.Advance(-1);
end;

procedure TRecordViewerFrame.acSaveAsExecute(Sender: TObject);
begin
  with SaveDialog do
  begin
    InitialDir := ExtractFileDir(FileName);
    FileName := ExtractFileName(FileName);
    if Execute then
      RecordViewerGrid.SaveRecordToFile(FileName);
  end;
end;

procedure TRecordViewerFrame.acSaveExecute(Sender: TObject);
begin
  if RecordViewerGrid.FileName = '' then
    acSaveAsExecute(nil)
  else
    RecordViewerGrid.SaveRecordToFile(RecordViewerGrid.FileName);
end;

procedure TRecordViewerFrame.ActionListUpdate(AAction: TBasicAction;
  var Handled: Boolean);
begin
  if AAction = acMoveUp then
    acMoveUp.Enabled := FGrid.Row > FGrid.FixedRows
  else if AAction = acMoveDown then
    acMoveDown.Enabled := FGrid.Row < FGrid.RowCount-1;
end;

function TRecordViewerFrame.CreateViewerGrid: TViewerGrid;
begin
  Result := TRecordViewerGrid.Create(self);
end;

function TRecordViewerFrame.GetDefaultColWidths(AIndex: Integer): Integer;
begin
  Result := DefaultHexParams.RecordViewerColWidths[AIndex];
end;

function TRecordViewerFrame.RecordViewerGrid: TRecordViewerGrid;
begin
  Result := (FGrid as TRecordViewerGrid);
end;

procedure TRecordViewerFrame.RestoreToolButtons;
var
  i: Integer;
begin
  case Toolbar.Align of
    alLeft, alRight:
      for i := High(FToolButtons) downto 0 do
      begin
        if FToolButtons[i].Style = tbsDivider then
          FToolButtons[i].Height := 5;
        Toolbar.ButtonList.Exchange(i, 0);
      end;
    alTop, alBottom:
      for i := High(FToolButtons) downto 0 do
      begin
        if FToolButtons[i].Style = tbsDivider then
          FToolButtons[i].Width := 5;
        Toolbar.ButtonList.Exchange(i, 0);
      end;
  end;
end;

procedure TRecordViewerFrame.SetParent(AValue: TWinControl);
begin
  inherited SetParent(AValue);
  if (Parent <> nil) then begin
    case Parent.Align of
      alLeft, alRight:
        Toolbar.Align := alTop;
      alTop, alBottom:
        Toolbar.Align := alLeft;
    end;
    ToolBar.AutoSize := true;
    RestoreToolButtons;
  end;
end;

end.
