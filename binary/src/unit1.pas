unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, IniFiles, FileUtil, fpjson, jsonparser, LazUTF8, SHA1;

type
  // 各 "form" の情報を保持するレコード
  TFormField = record
    LabelStr: string;  // JSON上の label
    Memo: TMemo;   // 生成した TMemo への参照
  end;

  // 各 "term" (metadataSchemaの要素) の情報を保持するレコード
  TTermInfo = record
    Number: integer;
    LabelStr: string;
    Requirement: string;
    Fields: array of TFormField;  // forms配列に対応
  end;

  { TForm1 }

  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    sourcePath: string;
    NasDataPath: string;
    DefaultSchema: string;
    MetaOutputFolder: string;
    MetaFileName: string;
    InstrumentId: string;
    InstrumentName: string;
    ScrollBox1: TScrollBox;
    SaveButton: TButton;
    procedure LoadAndCreateDynamicForm(const AFileName: string);
    // 「保存」ボタンのOnClickイベント：入力内容をJSONでまとめて保存
    procedure SaveButtonClick(Sender: TObject);
    procedure CopyFolder(const SourceDir, DestDir: string);
    procedure GetFolderSHA1AsJSON(const FolderPath: string;
      JsonArray: TJSONArray; const BasePath: string);

    function ReadSeqValue(const AFileName: string): integer;
    procedure WriteSeqValue(const AFileName: string; AValue: integer);
  public
    // 画面に表示しているフォーム定義を格納する配列
    TermList: array of TTermInfo;

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  Ini: TIniFile;
begin
  if ParamCount() >= 1 then
    sourcePath := ParamStr(1)
  else
    ShowMessage('転送するファイルまたはフォルダを指定してください');

  //sourcePath := 'C:\Users\takase\Desktop\sources\sources\fptest\ugoku';

  Ini := TIniFile.Create('config.ini');
  try
    // INIから設定を読み込み
    NasDataPath := Ini.ReadString('Path', 'NasDataPath', '');
    //NasMetaPath := Ini.ReadString('Path', 'NasMetaPath', '');
    DefaultSchema := Ini.ReadString('Meta', 'DefaultSchema', 'schema.json');
    MetaOutputFolder := Ini.ReadString('Meta', 'OutputFolder', 'meta');
    MetaFileName := Ini.ReadString('Meta', 'Name', 'meta.json');
    InstrumentId := Ini.ReadString('Instrument', 'InstrumentId', '機器ID');
    InstrumentName := Ini.ReadString('Instrument', 'InstrumentName', '機器名');
    //+ ' / Port = ' + IntToStr(ServerPort);
  finally
    Ini.Free;
  end;

  // スクロールボックスを作成して Form1 に貼り付け
  ScrollBox1 := TScrollBox.Create(Self);
  ScrollBox1.Parent := Self;
  ScrollBox1.Align := alClient;
  ScrollBox1.AutoScroll := True; // スクロールバーを表示

  // 「保存」ボタンをフォーム(ScrollBoxではなく)に配置し、下端に固定
  SaveButton := TButton.Create(Self);
  SaveButton.Parent := Self;
  SaveButton.Align := alBottom;
  SaveButton.Caption := '転送開始';
  SaveButton.Height := 40;
  SaveButton.OnClick := @SaveButtonClick;

  LoadAndCreateDynamicForm(DefaultSchema);
end;


procedure TForm1.LoadAndCreateDynamicForm(const AFileName: string);
var
  fs: TFileStream;
  parser: TJSONParser;
  JSONData: TJSONData;
  rootObj: TJSONObject;
  metaArray: TJSONArray;

  itemObj, formsObj: TJSONObject;
  formsArray: TJSONArray;

  i, j: integer;
  yPos: integer;

  newLabel: TLabel;
  newMemo: TMemo;

  // 一時的に使う構造体変数
  termInfo: TTermInfo;
  fieldInfo: TFormField;
begin
  if not FileExists(AFileName) then
  begin
    ShowMessage('File not found: ' + AFileName);
    Exit;
  end;

  // JSON をパース
  fs := TFileStream.Create(AFileName, fmOpenRead);
  try
    parser := TJSONParser.Create(fs, True);
    try
      JSONData := parser.Parse;
    finally
      parser.Free;
    end;
  finally
    fs.Free;
  end;

  if not (JSONData is TJSONObject) then
  begin
    ShowMessage('JSON がオブジェクトではありません。');
    JSONData.Free;
    Exit;
  end;

  rootObj := TJSONObject(JSONData);

  // "metadataSchema" 配列を取得
  metaArray := rootObj.Arrays['metadataSchema'];

  yPos := 10;  // ScrollBox 内に配置していくための Y 座標

  // TermList配列を JSON の要素数に合わせてリサイズ
  SetLength(TermList, metaArray.Count);

  // metadataSchema の各要素(term)を順番に処理
  for i := 0 to metaArray.Count - 1 do
  begin
    if metaArray.Items[i] is TJSONObject then
    begin
      itemObj := TJSONObject(metaArray.Items[i]);

      // termInfo に値をセット
      termInfo.Number := itemObj.Get('number', 0);
      termInfo.LabelStr := itemObj.Get('label', '');
      termInfo.Requirement := itemObj.Get('requirement', '');

      // 見出し用のラベルを作成
      newLabel := TLabel.Create(Self);
      newLabel.Parent := ScrollBox1;
      newLabel.Caption := Format('%d. %s [%s]',
        [termInfo.Number, termInfo.LabelStr, termInfo.Requirement]);
      newLabel.Top := yPos;
      newLabel.Left := 10;
      newLabel.Font.Style := [fsBold];
      Inc(yPos, 25);

      // "forms" 配列の処理
      formsArray := itemObj.Arrays['forms'];
      SetLength(termInfo.Fields, formsArray.Count);

      for j := 0 to formsArray.Count - 1 do
      begin
        if formsArray.Items[j] is TJSONObject then
        begin
          formsObj := TJSONObject(formsArray.Items[j]);

          // Label
          newLabel := TLabel.Create(Self);
          newLabel.Parent := ScrollBox1;
          newLabel.Caption := formsObj.Get('label', '');
          newLabel.Top := yPos;
          newLabel.Left := 30;

          // TMemoを動的作成
          newMemo := TMemo.Create(Self);
          newMemo.Parent := ScrollBox1;
          newMemo.Top := yPos;
          newMemo.Left := 160;
          newMemo.Width := 400;
          newMemo.Height := 40;
          newMemo.ScrollBars := ssAutoBoth;
          newMemo.WordWrap := True;
          if termInfo.Requirement = 'specified' then
          begin
            newMemo.ReadOnly:= true;
            if termInfo.LabelStr = 'Instrument id' then
               newMemo.Text := InstrumentId
            else if termInfo.LabelStr = 'Instrument name' then
               newMemo.Text := InstrumentName;
          end;

          // Anchor の設定: 左上に固定 (デフォルト)
          // これでユーザがメモの右下をドラッグしてサイズ変更可能
          newMemo.Anchors := [akTop, akLeft];
          //end;

          // ツールチップに表示
          newMemo.Hint := formsObj.Get('note', '');
          newMemo.ShowHint := (newMemo.Hint <> '');

          Inc(yPos, 50);

          // fieldInfo に格納 (将来 JSON 出力時に参照する)
          fieldInfo.LabelStr := formsObj.Get('label', '');
          fieldInfo.Memo := newMemo;

          termInfo.Fields[j] := fieldInfo;
        end;
      end;

      // termInfo を配列に記録
      TermList[i] := termInfo;

      // 項目ブロックの後、少しスペースを開ける
      Inc(yPos, 10);
    end;
  end;

  JSONData.Free;
end;

// 転送ボタンを押したときの処理
procedure TForm1.SaveButtonClick(Sender: TObject);
var
  i, j: integer;
  rootObj, termObj, formObj: TJSONObject;
  metaArray, formsArray, filesArray: TJSONArray;
  fs: TFileStream;
  s: string;
  newFolder: string;
  newMetaFolder: string;
  newMetaFile: string;
  seqFile: string;
  seqVal: integer;
  isRequired: Boolean;
  inputNashi: Boolean;
begin
  // 画面上の入力内容を元に JSON を組み立てる
  rootObj := TJSONObject.Create;
  metaArray := TJSONArray.Create;
  rootObj.Add('metadataSchema', metaArray);

  // TermList を元に出力用JSONを作成
  for i := 0 to High(TermList) do
  begin
    termObj := TJSONObject.Create;
    termObj.Add('number', TermList[i].Number);
    termObj.Add('label', TermList[i].LabelStr);
    termObj.Add('requirement', TermList[i].Requirement);

    formsArray := TJSONArray.Create;
    termObj.Add('forms', formsArray);

    isRequired := False;
    inputNashi := True;
    if (TermList[i].Requirement = 'oneRequired') or (TermList[i].Requirement = 'required') then
       isRequired := True;
    // 各フィールドの入力値を "value" として格納
    for j := 0 to High(TermList[i].Fields) do
    begin
      formObj := TJSONObject.Create;
      formObj.Add('label', TermList[i].Fields[j].LabelStr);
      // TMemo からテキストを取得して格納
      formObj.Add('value', TermList[i].Fields[j].Memo.Lines.Text);
      formsArray.Add(formObj);
      if Length(TermList[i].Fields[j].Memo.Lines.Text) > 0 then
         inputNashi := False;
    end;
    if isRequired and inputNashi then
    begin
      ShowMessage('必須項目が入力されていません: ' + TermList[i].LabelStr);
      Exit;
    end;
    metaArray.Add(termObj);
  end;

  // ファイル情報のJSONデータ作成
  filesArray := TJSONArray.Create;
  rootObj.Add('files', filesArray);
  GetFolderSHA1AsJSON(sourcePath, filesArray, sourcePath);

  // 転送先用意＆こぴー

  // seq.dat 読み込み & インクリメント
  seqFile := ExtractFilePath(Application.ExeName) + 'seq.dat';
  seqVal := ReadSeqValue(seqFile);
  // seq.dat をインクリメントして保存
  Inc(seqVal);
  WriteSeqValue(seqFile, seqVal);

  newFolder := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(NasDataPath) +
    InstrumentName + '_' + IntToStr(seqVal));
  newMetaFolder := IncludeTrailingPathDelimiter(newFolder + MetaOutputFolder);
  newMetaFile := newMetaFolder + MetaFileName;

  // 指定されたコピー元がファイルかどうかチェック
  if DirectoryExists(sourcePath) then
  begin
    CopyFolder(sourcePath, newFolder);
  end
  else if FileExists(sourcePath) then
  begin
    if not DirectoryExists(newFolder) then
      ForceDirectories(newFolder);
    if CopyFile(sourcePath, newFolder + ExtractFileName(sourcePath)) then
      ShowMessage('ファイル転送しました: ' + newFolder)
    else
      ShowMessage('ファイルの転送に失敗しました。');
  end
  else
  begin
    ShowMessage('コピー元フォルダが見つかりません');
  end;


  // METAファイルへ保存
  try
    if not DirectoryExists(newMetaFolder) then
    begin
      ForceDirectories(newMetaFolder);
      {$IFDEF WINDOWS}
                FileSetAttr(newMetaFolder, faHidden);
      {$ENDIF}
    end;

    fs := TFileStream.Create(newMetaFile, fmCreate);
    try
      s := rootObj.FormatJSON();
      fs.Write(Pointer(s)^, Length(s));
    finally
      fs.Free;
    end;
    //ShowMessage('メタデータを保存しました');

  finally
    rootObj.Free;  // JSONオブジェクト解放
  end;

end;

procedure TForm1.CopyFolder(const SourceDir, DestDir: string);
begin
  if not DirectoryExists(SourceDir) then
  begin
    ShowMessage('コピー元フォルダが見つかりません: ' + SourceDir);
    Exit;
  end;

  // 目的フォルダを作成（存在しない場合）
  if not DirectoryExists(DestDir) then
    ForceDirectories(DestDir);

  // LazFileUtils の CopyDirTree を使用
  if CopyDirTree(SourceDir, DestDir, [cffOverwriteFile, cffCreateDestDirectory]) then
    ShowMessage('転送が完了しました: ' + DestDir)
  else
    ShowMessage('転送に失敗しました: ' + DestDir);
end;

// 指定されたフォルダ内の全ファイルのMD5値を取得（サブフォルダも再帰的に処理）
procedure TForm1.GetFolderSHA1AsJSON(const FolderPath: string;
  JsonArray: TJSONArray; const BasePath: string);
var
  SR: TSearchRec;
  Res: integer;
  FilePath, RelativePath: string;
  JsonObject2: TJSONObject;
  LHandle    : Integer;
  LFileiDate : Integer;
  LFileDate  : TDateTime;
begin
  if not DirectoryExists(FolderPath) then Exit;

  Res := FindFirst(FolderPath + DirectorySeparator + '*.*', faAnyFile, SR);
  try
    while Res = 0 do
    begin
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        FilePath := FolderPath + DirectorySeparator + SR.Name;
        RelativePath := ExtractRelativePath(BasePath, FilePath);

        if DirectoryExists(FilePath) then
        begin
          // サブフォルダなら再帰的に処理
          GetFolderSHA1AsJSON(FilePath, JsonArray, BasePath);
        end
        else
        begin
          // ファイルならSHA1を取得してJSONに追加
          JsonObject2 := TJSONObject.Create;
          JsonObject2.Add('path', RelativePath);
          JsonObject2.Add('sha1', SHA1Print(SHA1File(FilePath)));

          LHandle := FileOpen(FilePath, fmOpenRead);
          try
            LFileiDate := FileGetDate(LHandle);
            LFileDate := FileDateToDateTime(LFileiDate);
            JsonObject2.Add('created', DateTimeToStr(LFileDate));
          finally
            FileClose(LHandle);
          end;

          JsonArray.Add(JsonObject2);
          //JsonObject2.Free;
        end;
      end;
      Res := FindNext(SR);

    end;
  finally

    FindClose(SR);
  end;
end;


//------------------------------------------------------------------------------
// seq.dat から現在の連番を読み込む
//------------------------------------------------------------------------------
function TForm1.ReadSeqValue(const AFileName: string): integer;
var
  sl: TStringList;
begin
  Result := 1; // デフォルト値
  if FileExists(AFileName) then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(AFileName);
      if sl.Count > 0 then
        Result := StrToIntDef(Trim(sl[0]), 1);
    finally
      sl.Free;
    end;
  end;
end;

//------------------------------------------------------------------------------
// seq.dat に連番を書き込む
//------------------------------------------------------------------------------
procedure TForm1.WriteSeqValue(const AFileName: string; AValue: integer);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Add(IntToStr(AValue));
    sl.SaveToFile(AFileName);
  finally
    sl.Free;
  end;
end;

end.
