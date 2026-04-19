// backend/URLFetcher.mo

import Text "mo:core/Text";

module {
  public type FetchResult = {
    #ok : { html : Text };
    #err : { error : Text; message : Text };
  };

  type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [{ name : Text; value : Text }];
    body : ?Blob;
    method : { #get; #post; #head };
    transform : ?{
      function : shared query ({ response : HttpResponse; context : Blob }) -> async HttpResponse;
      context : Blob;
    };
  };

  type HttpResponse = {
    status : Nat;
    headers : [{ name : Text; value : Text }];
    body : Blob;
  };

  type IC = actor {
    http_request : HttpRequestArgs -> async HttpResponse;
  };

  public func fetch(url : Text) : async FetchResult {
    if (url.size() == 0) {
      return #err({ error = "INVALID_INPUT"; message = "Field is required" });
    };

    let request : HttpRequestArgs = {
      url = url;
      max_response_bytes = ?2_000_000;
      headers = [
        { name = "User-Agent"; value = "Mozilla/5.0" },
        { name = "Accept"; value = "text/html" },
      ];
      body = null;
      method = #get;
      transform = null;
    };

    try {
      let ic : IC = actor ("aaaaa-aa");
      let response = await ic.http_request(request);
      switch (response.body.decodeUtf8()) {
        case (?text) #ok({ html = text });
        case null #err({ error = "FETCH_FAILED"; message = "Could not decode response body" });
      };
    } catch (_) {
      #err({ error = "FETCH_FAILED"; message = "Could not retrieve URL" });
    };
  };
};
