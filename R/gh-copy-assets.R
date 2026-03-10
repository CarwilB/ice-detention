library(htmltools)

include_table_assets <- function() {
  tagList(
    tags$style(HTML("
      .copy-btn {
        background-color: #24292e;
        color: white;
        border: 1px solid rgba(27,31,35,.15);
        padding: 5px 12px;
        font-size: 12px;
        font-weight: 600;
        border-radius: 6px;
        cursor: pointer;
        margin-bottom: 8px;
        transition: 0.2s;
      }
      .copy-btn:hover { background-color: #0366d6; }
      .copy-btn:active { transform: scale(0.98); }
    ")),
    tags$script(HTML("
      function copyTableToClipboard(id, btn) {
        var textArea = document.getElementById(id);
        textArea.select();
        textArea.setSelectionRange(0, 99999); // For mobile
        document.execCommand('copy');
        
        var originalText = btn.innerText;
        btn.innerText = '✔️ Copied!';
        btn.style.backgroundColor = '#28a745';
        
        setTimeout(function() {
          btn.innerText = originalText;
          btn.style.backgroundColor = '#24292e';
        }, 2000);
      }
    "))
  )
}

copy_to_clipboard_button_gh <- function(kable_input, button_label = "Copy GitHub Markdown") {
  # Generate a unique ID to prevent conflicts if you have multiple buttons
  table_id <- paste0("copy_target_", sample(1000:9999, 1))
  
  # Flatten the kable output into a single string
  raw_markdown <- paste(as.character(kable_input), collapse = "\n")
  
  htmltools::tagList(
    # 1. The Visible Button
    htmltools::tags$button(
      class = "copy-btn",
      onclick = sprintf("copyTableToClipboard('%s', this)", table_id),
      button_label
    ),
    
    # 2. The Hidden Storage
    # We use a textarea because it preserves line breaks and whitespace perfectly
    htmltools::tags$textarea(
      id = table_id,
      style = "position: absolute; left: -9999px; height: 0; width: 0; overflow: hidden;",
      readonly = TRUE,
      raw_markdown
    )
  )
}

copy_to_clipboard_button_wt <- function(kable_input, button_label = "Copy WikiText") {
  # Generate a unique ID to prevent conflicts if you have multiple buttons
  table_id <- paste0("copy_target_", sample(1000:9999, 1))
  
  # Flatten the kable output into a single string
  raw_markdown <- paste(as.character(kable_input), collapse = "\n")
  
  htmltools::tagList(
    # 1. The Visible Button
    htmltools::tags$button(
      class = "copy-btn",
      onclick = sprintf("copyTableToClipboard('%s', this)", table_id),
      button_label
    ),
    
    # 2. The Hidden Storage
    # We use a textarea because it preserves line breaks and whitespace perfectly
    htmltools::tags$textarea(
      id = table_id,
      style = "position: absolute; left: -9999px; height: 0; width: 0; overflow: hidden;",
      readonly = TRUE,
      raw_markdown
    )
  )
}
