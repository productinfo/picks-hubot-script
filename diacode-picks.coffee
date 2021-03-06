# Description
#   This plugin will listen for links in the specified HUBOT_PICKS_ROOM. 
#   Each link detected will be sent to HUBOT_PICKS_DISCOVER_URL where it'll be processed.
#   The links can also be edited through the chat using !edit and !approve commands.
#   The link_id is optional in all commands. When it isn't specified the bot will take it from
#   last added link.
#
# Configuration:
#   HUBOT_PICKS_DISCOVER_URL
#   HUBOT_PICKS_ROOM
#   HUBOT_PICKS_EMAIL
#   HUBOT_PICKS_API_TOKEN
#
# Commands:
#   <link> - Will send a link to Diacode Picks API
#   !edit [id_link] title <new_title> - Edit the title of a link
#   !edit [id_link] description <new_description> - Edit the description of a link
#   !edit [id_link] desc <new_description> - Edit the description of a link (alias)
#   !approve [id_link] - Approve a link
#   !delete [id_link] - Delete a link
#   !del [id_link] - Delete a link (alias)
#   !show [id_link] - Display all info stored of a link
#   !approved - Will show all approved & unused links in the buffer
#   !pending - Will show all pending & unused links in the buffer
#
# Author:
#   hopsor

apiEndpoint = process.env.HUBOT_PICKS_DISCOVER_URL
watchedRoom = process.env.HUBOT_PICKS_ROOM
userEmail = process.env.HUBOT_PICKS_EMAIL
apiToken = process.env.HUBOT_PICKS_API_TOKEN
brain = null

# ==============
# Custom methods
# ==============

# validateConfiguration: Checks all ENV variables are properly set
validateConfiguration = (msg) ->
  if !apiEndpoint || !watchedRoom || !userEmail || !apiToken 
    msg.send "You have to set these four environment variables:"
    msg.send "HUBOT_PICKS_DISCOVER_URL, HUBOT_PICKS_ROOM, HUBOT_PICKS_EMAIL, HUBOT_PICKS_API_TOKEN"
    return false
  else return true

# validateRoom: Returns true if the message room matches HUBOT_PICKS_ROM environment variable 
validateRoom = (msg) ->
  msg.envelope.room == watchedRoom

validateLinkId = (linkId, msg) ->
  if isNaN(parseInt(linkId))
    msg.send "Error: link id not found. Please specify it explicitly"
    return false
  else
    return true

# apiRequestCompleted: Method to process a response after sending an API request
apiRequestCompleted = (err, res, body, msg, callback) ->
  if err
    msg.send "Encountered an error :( #{err}"
    return

  if res.statusCode < 200 || res.statusCode > 299
    msg.send "Request didn't come back HTTP 200 :("
    return

  linkData = {}

  try
    linkData = JSON.parse(body) if body != ''
    callback(linkData)
  catch error
    msg.send "Ran into an error parsing JSON response :("
    return

# sendApiRequest: Make api requests
sendApiRequest = (msg, endPoint, params, method, callback) ->
  stringParams = JSON.stringify(params)

  request = msg.http(endPoint)
    .headers(
      'Accept': 'application/json'
      'Content-Length': stringParams.length
      'Content-Type': 'application/json'
      'Authorization': "Token token=\"#{apiToken}\", email=\"#{userEmail}\""
    )

  switch method
    when 'get'
      request.get(stringParams) (err, res, body) -> apiRequestCompleted(err, res, body, msg, callback)
    when 'post'
      request.post(stringParams) (err, res, body) -> apiRequestCompleted(err, res, body, msg, callback)
    when 'put'
      request.put(stringParams) (err, res, body) -> apiRequestCompleted(err, res, body, msg, callback)   
    when 'delete'
      request.delete(stringParams) (err, res, body) -> apiRequestCompleted(err, res, body, msg, callback)    

# ======================
# Bot action definitions
# ======================
addLink = (msg) ->
  return unless validateConfiguration(msg)
  return unless validateRoom(msg)

  params = 
    link:
      url: msg.message.text.replace("amp;", "")

  sendApiRequest(msg, apiEndpoint, params, 'post', (linkData) ->
    brain.set 'lastLinkId', linkData.link.id
    msg.send "Link processed and saved with ID #{linkData.link.id}"
    msg.send "*Title*: #{linkData.link.title}"
    msg.send "*Description*: #{linkData.link.description}"
  )    

editLink = (msg) ->
  return unless validateConfiguration(msg)
  return unless validateRoom(msg)

  editionRegex = /^!edit ?([0-9]+)? (title|description|desc) (.*)$/i
  matches = editionRegex.exec(msg.message.text)
  linkId = matches[1]
  linkId ||= brain.get('lastLinkId')
  return unless validateLinkId(linkId, msg)

  params = {}
  params.link = {}

  attributeToModify = if matches[2] == 'desc' then 'description' else matches[2]

  params.link[attributeToModify] = matches[3]

  sendApiRequest(msg, "#{apiEndpoint}/#{linkId}", params, 'put', ->
    msg.send "Link #{linkId} updated successfully"
  )

approveLink = (msg) ->
  return unless validateConfiguration(msg)
  return unless validateRoom(msg)

  approvalRegex = /^!approve ?([0-9]+)?$/i
  matches = approvalRegex.exec(msg.message.text)
  linkId = matches[1]
  linkId ||= brain.get('lastLinkId')
  return unless validateLinkId(linkId, msg)

  params = 
    link:
      approved: true

  sendApiRequest(msg, "#{apiEndpoint}/#{linkId}", params, 'put', ->
    msg.send "Link #{linkId} approved successfully"
  )

deleteLink = (msg) ->
  return unless validateConfiguration(msg)
  return unless validateRoom(msg)

  removalRegex = /^!del(ete)? ?([0-9]+)?$/i
  matches = removalRegex.exec(msg.message.text)
  linkId = matches[2]
  linkId ||= brain.get('lastLinkId')
  return unless validateLinkId(linkId, msg)

  sendApiRequest(msg, "#{apiEndpoint}/#{linkId}", {}, 'delete', ->
    msg.send "Link #{linkId} deleted successfully"
  )

listApproved = (msg) ->  
  return unless validateConfiguration(msg)
  return unless validateRoom(msg)

  sendApiRequest(msg, "#{apiEndpoint}", {approved: 'true'}, 'get', (data) ->
    linkList = ""
    links = data.links

    msg.send("There are #{links.length} links approved")

    for link in links
      linkList += "##{link.id} - #{link.title} #{link.url}\n"

    msg.send(linkList)
  )

listPending = (msg) ->  
  return unless validateConfiguration(msg)
  return unless validateRoom(msg)

  sendApiRequest(msg, "#{apiEndpoint}", {approved: 'false'}, 'get', (data) ->
    linkList = ""
    links = data.links

    msg.send("There are #{links.length} links pending")

    for link in links
      linkList += "##{link.id} - #{link.title} #{link.url}\n"

    msg.send(linkList)
  )

showLink = (msg) ->  
  return unless validateConfiguration(msg)
  return unless validateRoom(msg)

  showRegex = /^!show ?([0-9]+)?$/i
  matches = showRegex.exec(msg.message.text)
  linkId = matches[1]
  linkId ||= brain.get('lastLinkId')
  return unless validateLinkId(linkId, msg)

  sendApiRequest(msg, "#{apiEndpoint}/#{linkId}", {}, 'get', (linkData) ->
    linkInfo = """
    *Title*: #{linkData.link.title}
    *Description*: #{linkData.link.description}
    *URL*: #{linkData.link.url}
    """
    msg.send(linkInfo)
  )

module.exports = (robot) ->
  brain = robot.brain
  robot.hear /^(?:(?:https?):\/\/)(?:\S+(?::\S*)?@)?(?:(?!10(?:\.\d{1,3}){3})(?!127(?:\.\d{1,3}){3})(?!169\.254(?:\.\d{1,3}){2})(?!192\.168(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z\u00a1-\uffff0-9]+-?)*[a-z\u00a1-\uffff0-9]+)(?:\.(?:[a-z\u00a1-\uffff0-9]+-?)*[a-z\u00a1-\uffff0-9]+)*(?:\.(?:[a-z\u00a1-\uffff]{2,})))(?::\d{2,5})?(?:\/[^\s]*)?$/i, addLink
  robot.hear /^!edit ?([0-9]+)? (title|description|desc) (.*)$/i, editLink
  robot.hear /^!approve ?([0-9]+)?$/i, approveLink
  robot.hear /^!del(ete)? ?([0-9]+)?$/i, deleteLink
  robot.hear /^!show ?([0-9]+)?$/i, showLink
  robot.hear /^!approved$/, listApproved
  robot.hear /^!pending$/, listPending
