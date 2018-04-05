$ ->
  refreshToken = ->
    token = currentPlayer.media.src.split('?')[1]
    if token && token.match(/^token=/)
      mount_point = $('body').data('mountpoint') || '/'
      $.get("#{mount_point}authorize.txt?#{token}")
        .done -> console.log("Token refreshed")
        .fail -> console.error("Token refresh failed")

  setInterval(refreshToken, 5*60*1000)
