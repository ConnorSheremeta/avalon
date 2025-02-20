# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
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


require 'active_model'

module Avalon
  module Batch
    class Entry
      extend ActiveModel::Translation
      include ActionView::Helpers::TranslationHelper

      attr_reader :fields, :files, :opts, :row, :errors, :manifest, :collection

      def initialize(fields, files, opts, row, manifest)
        @fields = fields
        @files  = files
        @opts   = opts
        @row    = row
        @manifest = manifest
        @errors = ActiveModel::Errors.new(self)
        @files.each { |file| file[:file] = File.join(@manifest.package.dir, file[:file]) }
      end

      def media_object
        return @media_object if @media_object
        @media_object = nil
        if fields[:media_object].present?
          begin
            @media_object = MediaObject.find(fields[:media_object].first)
          rescue ActiveFedora::ObjectNotFoundError => e
            @errors.add(:media_object, e.message)
            return nil
          end
        else
          @media_object = MediaObject.new(avalon_uploader: @manifest.package.user.user_key, 
                                          collection: @manifest.package.collection)
        end
        update_media_object
        return @media_object
      end

      def update_media_object
        @media_object.tap do |mo|
          mo.workflow.origin = 'batch'
          if Avalon::BibRetriever.configured? and fields[:bibliographic_id].present?
            begin
              mo.descMetadata.
                populate_from_catalog!(fields[:bibliographic_id].first,
                                       Array(fields[:bibliographic_id_label]).first)
            rescue Exception => e
              @errors.add(:bibliographic_id, e.message)
            end
            # Sometimes we want to override the bib import data for some of the
            # required fields (particularly if import data doesn't pass validations)
            mo.update_datastream(:descMetadata,
                                 fields.slice(:language,
                                              :topical_subject,
                                              :genre))
          else
            mo.update_datastream(:descMetadata, fields.except(:media_object))
          end
        end
      end

      def valid?
        # Set errors if does not validate against media_object model
        media_object.valid?
        media_object.errors.messages.each_pair { |field,errs|
          errs.each { |err| @errors.add(field, err) }
        }
        files = @files.select {|file_spec| file_valid?(file_spec)}
        if fields[:media_object].present?
          # Ensure files are NOT listed
          @errors.add(:content, "Both a metadata update, and files listed for processing! "\
                      "(Must be one or the other)") unless files.empty?
        else
          # Ensure files are listed
          @errors.add(:content, "No files listed") if files.empty?
        end
        # Replace collection error if collection not found
        if media_object.collection.nil?
          @errors.messages[:collection] = ["Collection not found: #{@fields[:collection].first}"]
          @errors.messages.delete(:governing_policy)
        end

        return @errors.messages.empty?
      end

      def file_valid?(file_spec)
        valid = true
        # Check date_digitized for valid format
        if file_spec[:date_digitized].present?
          begin
            DateTime.parse(file_spec[:date_digitized])
          rescue ArgumentError
            @errors.add(:date_digitized, "Invalid date_digitized: #{file_spec[:date_digitized]}. Recommended format: yyyy-mm-dd.")
            valid = false
          end
        end
        # Check file offsets for valid format
        if file_spec[:offset].present? && !Avalon::Batch::Entry.offset_valid?(file_spec[:offset])
          @errors.add(:offset, "Invalid offset: #{file_spec[:offset]}")
          valid = false
        end
        # Ensure listed files exist
        if File.file?(file_spec[:file]) && self.class.derivativePaths(file_spec[:file]).present?
          @errors.add(:content, "Both original and derivative files found")
          valid = false
        elsif File.file?(file_spec[:file])
          #Do nothing.
        else
          if self.class.derivativePaths(file_spec[:file]).present? && file_spec[:skip_transcoding]
            #Do nothing.
          elsif self.class.derivativePaths(file_spec[:file]).present? && !file_spec[:skip_transcoding]
            @errors.add(:content, "Derivative files found but skip transcoding not selected")
            valid = false
          else
            @errors.add(:content, "File not found: #{file_spec[:file]}")
            valid = false
          end
        end
        valid
      end

      def self.offset_valid?( offset )
        tokens = offset.split(':')
        return false unless (1...4).include? tokens.size
        seconds = tokens.pop
        return false unless /^\d{1,2}([.]\d*)?$/ =~ seconds
        return false unless seconds.to_f < 60
        unless tokens.empty?
          minutes = tokens.pop
          return false unless /^\d{1,2}$/ =~ minutes
          return false unless minutes.to_i < 60
          unless tokens.empty?
            hours = tokens.pop
            return false unless /^\d{1,}$/ =~ hours
          end
        end
        true
      end

      def self.attach_datastreams_to_master_file( master_file, filename )
        structural_file = "#{filename}.structure.xml"
        if File.exists? structural_file
          master_file.structuralMetadata.content=File.open(structural_file)
        end
        captions_file = "#{filename}.vtt"
        if File.exists? captions_file
          master_file.captions.content=File.open(captions_file)
          master_file.captions.mimeType='text/vtt'
          master_file.captions.dsLabel=captions_file
        end
      end

      def process!
        save_tries = 0
        begin
          media_object.save
        rescue Exception => error
          save_tries += 1
          # Report that an exception was caught for this object
          msg = t('batch_ingest.logger.object_error',
                       id: media_object.id, msg: error.inspect)
          manifest.manifest_logger.
            info(t('batch_ingest.logger.row_msg', row: row, msg: msg))
          logger.warn(msg)
          raise error if save_tries >=3
          sleep 3
          retry
        end
        # Report in the log what Fedora ID was assigned
        manifest.manifest_logger.info(t('batch_ingest.logger.row_msg',
                                             row: row, msg: "MediaObject #{media_object.pid}"))

        @files.each do |file_spec|
          master_file = MasterFile.new
          master_file.save(validate: false) #required: need pid before setting mediaobject
          master_file.mediaobject = media_object
          files = self.class.gatherFiles(file_spec[:file])
          self.class.attach_datastreams_to_master_file(master_file, file_spec[:file])
          master_file.setContent(files)
          master_file.absolute_location = file_spec[:absolute_location] if file_spec[:absolute_location].present?
          master_file.label = file_spec[:label] if file_spec[:label].present?
          master_file.poster_offset = file_spec[:offset] if file_spec[:offset].present?
          master_file.date_digitized = DateTime.parse(file_spec[:date_digitized]).to_time.utc.iso8601 if file_spec[:date_digitized].present?

          #Make sure to set content before setting the workflow 
          master_file.set_workflow(file_spec[:skip_transcoding] ? 'skip_transcoding' : nil)
          save_tries = 0
          begin
            saved = media_object.save
          rescue Exception => error
            save_tries +=1
            logger.warn "Batch Ingest caught error on #{media_object.id}: #{error.inspect}"
            raise error if save_tries >=3
            sleep 3
            retry
          end
          if saved
            save_tries = 0
            begin
              media_object.save(validate: false)
            rescue Exception => error
              save_tries +=1
              logger.warn "Batch Ingest caught error on #{media_object.id}: #{error.inspect}"
              raise error if save_tries >=3
              sleep 3
              retry
            end
            master_file.process(files)
          else
            logger.error "Problem saving MasterFile(#{master_file.pid}): #{master_file.errors.full_messages.to_sentence}"
          end
        end
        context = {media_object: { pid: media_object.pid, access: 'private' }, mediaobject: media_object, user: @manifest.package.user.user_key, hidden: opts[:hidden] ? '1' : nil }
        HYDRANT_STEPS.get_step('access-control').execute context
        media_object.workflow.last_completed_step = 'access-control'

        if opts[:publish]
          media_object.publish!(@manifest.package.user.user_key)
          media_object.workflow.publish
        end

        begin
          saved = media_object.save
        rescue Exception => error
          save_tries +=1
          logger.warn "Batch Ingest caught error on #{media_object.id}: #{error.inspect}"
          raise error if save_tries >=3
          sleep 3
          retry
        end

        unless saved
          logger.error "Problem saving MediaObject: #{media_object}"
        end


        unless media_object.save
          logger.error "Problem saving MediaObject: #{media_object}"
        end

        media_object
      end

      def self.gatherFiles(file)
        derivatives = {}
        %w(low medium high).each do |quality|
          derivative = self.derivativePath(file, quality)
          derivatives["quality-#{quality}"] = File.new(derivative) if File.file? derivative
        end
        derivatives.empty? ? File.new(file) : derivatives
      end

      def self.derivativePaths(filename)
        paths = []
        %w(low medium high).each do |quality|
          derivative = self.derivativePath(filename, quality)
          paths << derivative if File.file? derivative
        end
        paths
      end

      def self.derivativePath(filename, quality)
        filename.dup.insert(filename.rindex('.'), ".#{quality}")
      end

    end
  end
end
