# Copyright 2011-2013, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed 
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the 
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

module ControllerMacros
  def login_as(factory_model = 'student', options = {})
    user = FactoryGirl.create(factory_model, options)
    @request.env["devise.mapping"] = Devise.mappings[:user]
    logger.debug "Attempting to sign in user: #{user}"
    sign_in user
    user
  end 
  def login_user(username)
    key = username =~ /@/ ? :email : :username
    user = User.where(key => username).first
    @request.env["devise.mapping"] = Devise.mappings[:user]
    logger.debug "Attempting to sign in user: #{user}"
    sign_in user
    user
  end
  def login_lti(factory_model = 'student', options = {virtual_groups: [Faker::Lorem.word]})
    user = FactoryGirl.create(factory_model, options)
    @request.env["devise.mapping"] = Devise.mappings[:user]
    logger.debug "Attempting to sign in user: #{user}"
    sign_in user
    @request.session[:virtual_groups] = user.virtual_groups
    user
  end
end
