import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Text "mo:base/Text";

module {
  public func arrayEq(chars : [Char], offset : Nat, sub : [Char]) : Bool {
    let subLen = sub.size();
    var k = 0;
    while (k < subLen) {
      if (chars[offset + k] != sub[k]) return false;
      k += 1;
    };
    true;
  };

  public func textSlice(t : Text, start : Nat, end : Nat) : Text {
    let chars = Text.toArray(t);
    if (start >= end) return "";
    let actualEnd = if (end > chars.size()) chars.size() else end;
    var res = "";
    var i = start;
    while (i < actualEnd) {
      res #= Text.fromChar(chars[i]);
      i += 1;
    };
    res;
  };

  public func findFirst(t : Text, sub : Text) : ?Nat {
    let chars = Text.toArray(t);
    let subChars = Text.toArray(sub);
    let len = chars.size();
    let subLen = subChars.size();
    var i = 0;
    while (i + subLen <= len) {
      if (arrayEq(chars, i, subChars)) return ?i;
      i += 1;
    };
    null;
  };

  public func findLast(t : Text, sub : Text) : ?Nat {
    let chars = Text.toArray(t);
    let subChars = Text.toArray(sub);
    let lenInt : Int = chars.size();
    let subLenInt : Int = subChars.size();
    if (lenInt < subLenInt) return null;
    var i : Int = lenInt - subLenInt;
    while (i >= 0) {
      let idx = Int.abs(i);
      if (arrayEq(chars, idx, subChars)) {
        return ?idx;
      };
      i -= 1;
    };
    null;
  };

  public func extractStringField(obj : Text, field : Text) : ?Text {
    let key = "\"" # field # "\"";
    let chars = Text.toArray(obj);
    let keyChars = Text.toArray(key);
    let keyLen = keyChars.size();
    let len = chars.size();
    var i = 0;
    while (i + keyLen <= len) {
      if (arrayEq(chars, i, keyChars)) {
        var j = i + keyLen;
        while (j < len and (chars[j] == ' ' or chars[j] == ':' or chars[j] == '\n' or chars[j] == '\r' or chars[j] == '\t')) { j += 1 };
        if (j < len and chars[j] == '\"') {
          j += 1;
          var value = "";
          var escape = false;
          while (j < len) {
            let c = chars[j];
            if (escape) {
              if (c == 'n') { value #= "\n" }
              else if (c == 't') { value #= "\t" }
              else if (c == 'r') { value #= "\r" }
              else { value #= Text.fromChar(c) };
              escape := false;
            } else if (c == '\\') {
              escape := true;
            } else if (c == '\"') {
              return ?value;
            } else {
              value #= Text.fromChar(c);
            };
            j += 1;
          };
        };
      };
      i += 1;
    };
    null;
  };

  public func extractNatField(obj : Text, field : Text) : ?Nat {
    let key = "\"" # field # "\"";
    let chars = Text.toArray(obj);
    let keyChars = Text.toArray(key);
    let keyLen = keyChars.size();
    let len = chars.size();
    var i = 0;
    while (i + keyLen <= len) {
      if (arrayEq(chars, i, keyChars)) {
        var j = i + keyLen;
        // Skip whitespace and the colon
        while (j < len and (chars[j] == ' ' or chars[j] == ':' or chars[j] == '\n' or chars[j] == '\r' or chars[j] == '\t')) { j += 1 };
        var num : Nat = 0;
        var foundDigits = false;
        // Read digits directly to avoid complex type casting
        while (j < len) {
          let c = chars[j];
          if (c == '0') { num := num * 10 + 0; foundDigits := true; }
          else if (c == '1') { num := num * 10 + 1; foundDigits := true; }
          else if (c == '2') { num := num * 10 + 2; foundDigits := true; }
          else if (c == '3') { num := num * 10 + 3; foundDigits := true; }
          else if (c == '4') { num := num * 10 + 4; foundDigits := true; }
          else if (c == '5') { num := num * 10 + 5; foundDigits := true; }
          else if (c == '6') { num := num * 10 + 6; foundDigits := true; }
          else if (c == '7') { num := num * 10 + 7; foundDigits := true; }
          else if (c == '8') { num := num * 10 + 8; foundDigits := true; }
          else if (c == '9') { num := num * 10 + 9; foundDigits := true; }
          else {
            if (foundDigits) return ?num else return null;
          };
          j += 1;
        };
        if (foundDigits) return ?num;
      };
      i += 1;
    };
    null;
  };

  public func extractStringArray(obj : Text) : [Text] {
    var items = Buffer.Buffer<Text>(8);
    let chars = Text.toArray(obj);
    let len = chars.size();
    var i = 0;
    var inQuotes = false;
    var currentStr = "";
    var escape = false;

    while (i < len) {
      let c = chars[i];
      if (escape) {
        if (c == 'n') { currentStr #= "\n" }
        else if (c == 't') { currentStr #= "\t" }
        else if (c == 'r') { currentStr #= "\r" }
        else { currentStr #= Text.fromChar(c) };
        escape := false;
      } else if (c == '\\') {
        escape := true;
      } else if (c == '\"') {
        if (inQuotes) {
          items.add(currentStr);
          currentStr := "";
          inQuotes := false;
        } else {
          inQuotes := true;
        };
      } else {
        if (inQuotes) {
          currentStr #= Text.fromChar(c);
        };
      };
      i += 1;
    };
    Buffer.toArray(items);
  };
};