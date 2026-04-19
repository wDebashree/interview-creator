// backend/main.mo

import Text "mo:core/Text";
import Char "mo:core/Char";
import URLFetcher "URLFetcher";
import JobParser "JobParser";
import SkillExtractor "SkillExtractor";
import QAGenerator "QAGenerator";

actor {
  public query func http_request(req : HttpRequest) : async HttpResponse {
    { status_code = 200; headers = [("Content-Type", "text/plain")]; body = "OK".encodeUtf8(); upgrade = ?true };
  };

  public func http_request_update(req : HttpRequest) : async HttpResponse {
    let path = req.url;
    let bodyText = switch (req.body.decodeUtf8()) {
      case (?t) t;
      case null return errorResponse(400, "INVALID_INPUT", "Request body is not valid UTF-8");
    };

    if (path == "/v1/process") {
      await handleProcess(bodyText);
    } else {
      errorResponse(404, "NOT_FOUND", "Endpoint not found");
    };
  };

  func handleProcess(bodyText : Text) : async HttpResponse {
    let url = extractStringField(bodyText, "url");
    let text = extractStringField(bodyText, "text");

    let jobDescription : Text = switch (url, text) {
      case (?u, _) {
        if (u.size() == 0) {
          return errorResponse(400, "INVALID_INPUT", "url must not be empty");
        };
        let fetchResult = await URLFetcher.fetch(u);
        let html = switch (fetchResult) {
          case (#ok r) r.html;
          case (#err e) return errorResponse(502, e.error, e.message);
        };
        let parseResult = JobParser.parse(#html html);
        switch (parseResult) {
          case (#ok r) r.jobDescription;
          case (#err e) return errorResponse(422, e.error, e.message);
        };
      };
      case (null, ?t) {
        if (t.size() == 0) {
          return errorResponse(400, "INVALID_INPUT", "text must not be empty");
        };
        let parseResult = JobParser.parse(#text t);
        switch (parseResult) {
          case (#ok r) r.jobDescription;
          case (#err e) return errorResponse(422, e.error, e.message);
        };
      };
      case (null, null) {
        return errorResponse(400, "INVALID_INPUT", "Provide either 'url' or 'text'");
      };
    };

    let skillsResult = await SkillExtractor.extract(jobDescription);
    let skills = switch (skillsResult) {
      case (#ok r) r.skills;
      case (#err e) return errorResponse(422, e.error, e.message);
    };

    let qaResult = await QAGenerator.generate(skills, jobDescription);
    switch (qaResult) {
      case (#ok r) {
        let json = qaToJson(r.qa);
        jsonResponse(200, json);
      };
      case (#err e) errorResponse(422, e.error, e.message);
    };
  };

  func qaToJson(qa : [QAGenerator.QAGroup]) : Text {
    var groups = "";
    var first = true;
    for (g in qa.vals()) {
      if (not first) { groups #= "," };
      first := false;
      var items = "";
      var firstItem = true;
      for (q in g.questions.vals()) {
        if (not firstItem) { items #= "," };
        firstItem := false;
        items #= "{\"question\":" # jsonStr(q.question) # ",\"answer\":" # jsonStr(q.answer) # "}";
      };
      groups #= "{\"skill\":" # jsonStr(g.skill) # ",\"questions\":[" # items # "]}";
    };
    "{\"qa\":[" # groups # "]}";
  };

  func jsonStr(s : Text) : Text {
    let e1 = s.replace(#text "\\", "\\\\");
    let e2 = e1.replace(#text "\"", "\\\"");
    let e3 = e2.replace(#text "\n", "\\n");
    let e4 = e3.replace(#text "\r", "\\r");
    let e5 = e4.replace(#text "\t", "\\t");
    "\"" # e5 # "\"";
  };

  func jsonResponse(status : Nat16, body : Text) : HttpResponse {
    {
      status_code = status;
      headers = [("Content-Type", "application/json")];
      body = body.encodeUtf8();
      upgrade = null;
    };
  };

  func errorResponse(status : Nat16, error : Text, message : Text) : HttpResponse {
    jsonResponse(status, "{\"error\":" # jsonStr(error) # ",\"message\":" # jsonStr(message) # "}");
  };

  func extractStringField(json : Text, field : Text) : ?Text {
    let key = "\"" # field # "\"";
    let chars = json.toArray();
    let keyChars = key.toArray();
    let keyLen = keyChars.size();
    let len = chars.size();
    let dquote = Char.fromNat32(34);
    let backslash = Char.fromNat32(92);
    var i = 0;

    while (i + keyLen <= len) {
      if (arrayEq(chars, i, keyChars)) {
        var j = i + keyLen;
        while (j < len and (chars[j] == ' ' or chars[j] == ':')) { j += 1 };
        if (j < len and chars[j] == dquote) {
          j += 1;
          var value = "";
          var escape = false;
          while (j < len) {
            let c = chars[j];
            if (escape) {
              value #= Text.fromChar(c);
              escape := false;
            } else if (c == backslash) {
              escape := true;
            } else if (c == dquote) {
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

  func arrayEq(chars : [Char], offset : Nat, sub : [Char]) : Bool {
    let subLen = sub.size();
    var k = 0;
    while (k < subLen) {
      if (chars[offset + k] != sub[k]) return false;
      k += 1;
    };
    true;
  };

  type HttpRequest = {
    method : Text;
    url : Text;
    headers : [(Text, Text)];
    body : Blob;
  };

  type HttpResponse = {
    status_code : Nat16;
    headers : [(Text, Text)];
    body : Blob;
    upgrade : ?Bool;
  };
};
